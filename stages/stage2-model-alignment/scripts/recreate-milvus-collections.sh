#!/bin/bash
#
# Recreate Milvus Collections with Proper Schema for LlamaStack
#
# This script drops existing collections and recreates them with the schema
# required by LlamaStack's remote::milvus provider:
#   - id: VarChar (primary key, max_length=128)
#   - vector: FloatVector (dim=768 for Granite embeddings)
#   - content: VarChar (max_length=60000 for chunk text)
#   - metadata: VarChar (max_length=2000 for JSON metadata)
#

set -e

NAMESPACE="${NAMESPACE:-private-ai-demo}"

echo "════════════════════════════════════════════════════════════════"
echo "🔧 Recreating Milvus Collections with Proper Schema"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Namespace: $NAMESPACE"
echo ""

# Run Python script in a temporary pod
oc run -n "$NAMESPACE" milvus-recreate-collections --rm -i --restart=Never \
  --image=registry.access.redhat.com/ubi9/python-311:1-77 \
  -- /bin/bash -c '
set -e

pip install --quiet pymilvus

python3 << "PYEOF"
from pymilvus import (
    connections, utility, Collection, 
    FieldSchema, CollectionSchema, DataType
)

# Connect to Milvus
print("Connecting to Milvus...")
connections.connect(
    alias="default",
    host="milvus-standalone.private-ai-demo.svc.cluster.local",
    port="19530"
)
print("✅ Connected")
print()

# Collections to recreate
collections = ["acme_corporate", "red_hat_docs", "eu_ai_act"]

for coll_name in collections:
    print("=" * 60)
    print(f"Collection: {coll_name}")
    print("=" * 60)
    
    # Drop if exists
    if utility.has_collection(coll_name):
        print(f"Dropping existing collection...")
        utility.drop_collection(coll_name)
        print(f"✅ Dropped")
    
    # Define MINIMAL schema: pk + vector only
    # LlamaStack provider stores chunks in dynamic 'chunk_content' field automatically
    # No explicit content/metadata fields needed - provider handles structure
    pk_field = FieldSchema(
        name="pk",
        dtype=DataType.INT64,
        is_primary=True,
        auto_id=True  # Milvus auto-generates Int64 IDs
    )
    vector_field = FieldSchema(
        name="vector",
        dtype=DataType.FLOAT_VECTOR,
        dim=768  # Granite embedding dimension
    )
    
    fields = [pk_field, vector_field]
    
    schema = CollectionSchema(
        fields=fields,
        description=f"RAG collection for {coll_name} scenario",
        enable_dynamic_field=True  # Allow extra fields from pipeline
    )
    
    # Create collection
    print("Creating collection with MINIMAL schema:")
    print("  • pk: Int64 (auto_id=true) [PRIMARY KEY]")
    print("  • vector: FloatVector(dim=768)")
    print("  • enable_dynamic_field: true (all other fields stored dynamically)")
    
    collection = Collection(name=coll_name, schema=schema)
    print(f"✅ Created")
    
    # Create index on vector field
    # Use HNSW to align with LlamaStack search params (M=16, efConstruction=200)
    print(f"Creating index on vector field...")
    index_params = {
        "index_type": "HNSW",
        "metric_type": "L2",
        "params": {
            "M": 16,
            "efConstruction": 200
        }
    }
    collection.create_index(
        field_name="vector",
        index_params=index_params
    )
    print(f"✅ Index created (HNSW, L2, M=16, efConstruction=200)")
    
    # Load collection
    collection.load()
    print(f"✅ Collection loaded")
    
    print()

print("=" * 60)
print("✅ All collections recreated successfully")
print("=" * 60)
print()

# Verify
print("Verification:")
for coll_name in collections:
    if utility.has_collection(coll_name):
        coll = Collection(coll_name)
        print(f"  ✅ {coll_name}: {coll.num_entities} entities")
    else:
        print(f"  ❌ {coll_name}: NOT FOUND")

print()
print("Collections are ready for LlamaStack ingestion!")
print()

PYEOF
'

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ Collections Recreated"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Apply updated LlamaStack configuration: oc apply -k gitops/stage02-model-alignment/llama-stack/"
echo "  2. Wait for LlamaStack pod to restart"
echo "  3. Run test insert to verify"
echo ""

