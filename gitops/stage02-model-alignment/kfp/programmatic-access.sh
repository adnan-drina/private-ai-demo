#!/bin/bash
# Programmatic KFP API Access Example
# Demonstrates OAuth authentication with DSPA

set -e

NAMESPACE="private-ai-demo"

# Get DSPA route and auth token
HOST="https://$(oc -n $NAMESPACE get route ds-pipeline-dspa -o jsonpath='{.spec.host}')"
TOKEN="$(oc whoami -t)"

echo "DSPA Host: $HOST"
echo "Token: ${TOKEN:0:20}..."
echo ""

# Test healthz endpoint
echo "Testing healthz endpoint..."
curl -sk -H "Authorization: Bearer $TOKEN" "$HOST/apis/v2beta1/healthz" | jq -r '.'

echo ""
echo "Listing pipelines..."
PIPELINES=$(curl -sk -H "Authorization: Bearer $TOKEN" "$HOST/apis/v2beta1/pipelines")
if echo "$PIPELINES" | jq -e '.pipelines' > /dev/null 2>&1; then
  echo "$PIPELINES" | jq -r '.pipelines[] | {id: .pipeline_id, name: .display_name}'
else
  echo "No pipelines found. Upload artifacts/docling-rag-pipeline.yaml via dashboard first."
fi

echo ""
echo "Python KFP Client Example:"
echo "─────────────────────────────────────────"

python3 - <<PY
from kfp import Client
import os

host = "$HOST"
token = "$TOKEN"

print(f"Connecting to: {host}")
c = Client(host=host, existing_token=token)

# List pipelines
pipelines = c.list_pipelines(page_size=10)
if pipelines.pipelines:
    print(f"\nFound {len(pipelines.pipelines)} pipeline(s):")
    for p in pipelines.pipelines:
        print(f"  - {p.display_name} (ID: {p.pipeline_id})")
else:
    print("\nNo pipelines found. Upload docling-rag-pipeline.yaml via dashboard first.")
PY
