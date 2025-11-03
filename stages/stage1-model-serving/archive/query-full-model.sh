#!/bin/bash
set -e

# Discover Model Registry host
MR_HOST=$(oc get route private-ai-model-registry-http -n rhoai-model-registries -o jsonpath='{.spec.host}' 2>/dev/null)

if [ -z "$MR_HOST" ]; then
  echo "❌ ERROR: Model Registry route not found"
  exit 1
fi

API_BASE="https://$MR_HOST/api/model_registry/v1alpha3"

echo "═══════════════════════════════════════════════════════════════════"
echo "🔍 QUERYING MODEL REGISTRY FOR FULL MODEL"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Model Registry: $MR_HOST"
echo ""

# Find Mistral-Small-24B-Instruct model
echo "1️⃣  Finding registered model..."
MODELS=$(curl -sk "$API_BASE/registered_models" -H "Accept: application/json")

MODEL_ID=$(echo "$MODELS" | python3 << 'PYEOF'
import sys, json
data = json.load(sys.stdin)
for model in data.get('items', []):
    if model.get('name') == 'Mistral-Small-24B-Instruct':
        print(model.get('id', ''))
        sys.exit(0)
print('')
PYEOF
)

if [ -z "$MODEL_ID" ]; then
  echo "❌ Model 'Mistral-Small-24B-Instruct' not found"
  exit 1
fi

echo "✅ Found: Mistral-Small-24B-Instruct (ID: $MODEL_ID)"
echo ""

# Get all versions
echo "2️⃣  Getting all versions..."
VERSIONS=$(curl -sk "$API_BASE/model_versions?registeredModelId=$MODEL_ID" -H "Accept: application/json")

echo "$VERSIONS" | python3 << 'PYEOF'
import sys, json

data = json.load(sys.stdin)

print("Available versions:")
for v in data.get('items', []):
    name = v.get('name', 'unknown')
    vid = v.get('id', 'unknown')
    props = v.get('customProperties', {})
    
    # Try to find image tag
    image_tag = props.get('image_tag', {}).get('string_value', '')
    if not image_tag:
        image_tag = props.get('version_tag', {}).get('string_value', '')
    
    print(f"  • {name} (ID: {vid})")
    if image_tag:
        print(f"    Image Tag: {image_tag}")

print("")
print("─" * 67)
print("")

# Find full/fp16 version
full_version = None
for v in data.get('items', []):
    name = v.get('name', '').lower()
    if 'full-2501' in name or 'fp16-2501' in name or 'full' in name:
        full_version = v
        break

if not full_version:
    print("❌ Full model version not found")
    sys.exit(1)

vid = full_version.get('id', '')
vname = full_version.get('name', '')
props = full_version.get('customProperties', {})

# Extract properties
image_tag = props.get('image_tag', {}).get('string_value', '')
if not image_tag:
    image_tag = props.get('version_tag', {}).get('string_value', 'fp16-2501')

internal_uri = props.get('internal_image_uri', {}).get('string_value', '')
quay_uri = props.get('quay_image_uri', {}).get('string_value', '')

print(f"3️⃣  FULL MODEL VERSION DETAILS:")
print(f"═══════════════════════════════════════════════════════════════════")
print(f"")
print(f"Name: {vname}")
print(f"ID: {vid}")
print(f"Image Tag: {image_tag}")
print(f"")
print(f"Internal Registry URI:")
print(f"  {internal_uri}")
print(f"")
print(f"Quay.io URI:")
print(f"  {quay_uri}")
print(f"")
print(f"═══════════════════════════════════════════════════════════════════")
print(f"")
print(f"✅ FOR INFERENCESERVICE YAML:")
print(f"")
print(f"  modelregistry.opendatahub.io/model-version-id: \"{vid}\"")
print(f"  storageUri: \"oci://image-registry.openshift-image-registry.svc:5000/private-ai-demo/mistral-small-24b-instruct:{image_tag}\"")
print(f"")
print(f"═══════════════════════════════════════════════════════════════════")

# Save to files
with open('/tmp/mr_model_id.txt', 'w') as f:
    f.write(full_version.get('registeredModelId', ''))
with open('/tmp/mr_version_id.txt', 'w') as f:
    f.write(vid)
with open('/tmp/mr_image_tag.txt', 'w') as f:
    f.write(image_tag)
with open('/tmp/mr_version_name.txt', 'w') as f:
    f.write(vname)

PYEOF

