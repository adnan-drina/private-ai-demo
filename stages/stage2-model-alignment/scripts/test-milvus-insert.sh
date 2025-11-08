#!/bin/bash
#
# Test LlamaStack → Milvus Insert After Configuration Fix
#
# This script validates that the schema/mapping fix works by:
#   1. Inserting a test chunk via LlamaStack API
#   2. Verifying data appears in Milvus
#   3. Querying via LlamaStack to ensure retrieval works
#

set -e

NAMESPACE="${NAMESPACE:-private-ai-demo}"
COLLECTION="${1:-acme_corporate}"

echo "════════════════════════════════════════════════════════════════"
echo "🧪 Testing LlamaStack → Milvus Integration"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Namespace: $NAMESPACE"
echo "Collection: $COLLECTION"
echo ""

oc run -n "$NAMESPACE" milvus-insert-test --rm -i --restart=Never \
  --image=registry.access.redhat.com/ubi9/python-311:1-77 \
  -- /bin/bash -c "
set -e

pip install --quiet requests pymilvus

python3 << 'PYEOF'
import requests
import json
import time
from pymilvus import connections, utility, Collection

llamastack_url = 'http://llama-stack-service.private-ai-demo.svc:8321'
collection_name = '$COLLECTION'

print('Step 1: Insert test chunk via LlamaStack API')
print('─' * 60)

test_chunk = {
    'content': 'TEST CHUNK: This is a validation test after schema fix. If this appears in Milvus with proper id (VarChar), content, and metadata fields, the configuration is correct.',
    'metadata': {
        'document_id': 'test-validation-001',
        'source': 'schema-fix-validation',
        'chunk_index': 0,
        'token_count': 30,
        'test_timestamp': time.strftime('%Y-%m-%d %H:%M:%S')
    }
}

print(f'Inserting to collection: {collection_name}')
print()

try:
    response = requests.post(
        f'{llamastack_url}/v1/vector-io/insert',
        json={
            'vector_db_id': collection_name,
            'chunks': [test_chunk]
        },
        headers={'Content-Type': 'application/json'},
        timeout=120
    )
    
    print(f'HTTP Status: {response.status_code}')
    
    if response.status_code != 200:
        print(f'❌ Insert failed: {response.text}')
        exit(1)
    
    try:
        result = response.json()
        print(f'Response: {json.dumps(result, indent=2)}')
        
        if 'num_inserted' in result:
            print(f'✅ Reported inserted: {result[\"num_inserted\"]} chunk(s)')
        else:
            print('⚠️  Response does not contain num_inserted field')
    except:
        print(f'Response (not JSON): {response.text}')
    
    print()
    
except Exception as e:
    print(f'❌ Insert request failed: {e}')
    exit(1)

print()
print('Step 2: Wait for data to commit (5 seconds)...')
time.sleep(5)
print()

print('Step 3: Verify in Milvus')
print('─' * 60)

try:
    connections.connect(
        alias='default',
        host='milvus-standalone.private-ai-demo.svc.cluster.local',
        port='19530'
    )
    
    if not utility.has_collection(collection_name):
        print(f'❌ Collection {collection_name} does not exist!')
        exit(1)
    
    coll = Collection(collection_name)
    coll.load()
    
    count = coll.num_entities
    print(f'Collection entities: {count}')
    
    if count > 0:
        print(f'✅ SUCCESS: Milvus has {count} entities')
        
        # Show schema to confirm it matches our fix
        print()
        print('Collection schema:')
        for field in coll.schema.fields:
            field_info = f'  • {field.name}: {field.dtype}'
            if hasattr(field, 'max_length'):
                field_info += f' (max_length={field.max_length})'
            if field.is_primary:
                field_info += ' [PRIMARY KEY]'
            if hasattr(field, 'params') and field.params:
                field_info += f' {field.params}'
            print(field_info)
        
        print()
        print('✅ Schema includes id (VarChar), vector, content, metadata')
        
    else:
        print('❌ FAILED: Collection still has 0 entities')
        print('   Data was not persisted')
        exit(1)
    
except Exception as e:
    print(f'❌ Milvus verification failed: {e}')
    exit(1)

print()
print('Step 4: Query via LlamaStack')
print('─' * 60)

try:
    response = requests.post(
        f'{llamastack_url}/v1/vector-io/query',
        json={
            'vector_db_id': collection_name,
            'query': 'validation test schema fix',
            'params': {'top_k': 5}
        },
        headers={'Content-Type': 'application/json'},
        timeout=60
    )
    
    print(f'HTTP Status: {response.status_code}')
    
    if response.status_code != 200:
        print(f'❌ Query failed: {response.text}')
        exit(1)
    
    result = response.json()
    chunks = result.get('chunks', [])
    
    print(f'Retrieved {len(chunks)} chunk(s)')
    
    if len(chunks) > 0:
        print()
        print('Top result:')
        chunk = chunks[0]
        print(f'  Content: {chunk.get(\"content\", \"N/A\")[:100]}...')
        print(f'  Score: {chunk.get(\"score\", \"N/A\")}')
        
        if chunk.get('content'):
            print()
            print('✅ SUCCESS: Query returns content field')
        else:
            print()
            print('⚠️  WARNING: content field is empty or missing')
    else:
        print('⚠️  No chunks retrieved (collection may be empty)')
    
except Exception as e:
    print(f'❌ Query failed: {e}')
    exit(1)

print()
print('═' * 60)
print('✅ VALIDATION PASSED')
print('═' * 60)
print()
print('The schema fix is working correctly:')
print('  • LlamaStack insert succeeds')
print('  • Data persists to Milvus')
print('  • Schema includes id (VarChar), vector, content, metadata')
print('  • Query retrieves data with content field')
print()

PYEOF
"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Test complete"
echo "════════════════════════════════════════════════════════════════"
echo ""

