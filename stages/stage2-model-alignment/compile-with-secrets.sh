#!/bin/bash
#
# Compile Pipeline with Secret Injection
#
# This script compiles the KFP v2 pipeline and injects Kubernetes Secret
# references for MinIO credentials following Red Hat best practices.
#

set -e

echo "════════════════════════════════════════════════════════════════════════════════"
echo "🔧 COMPILING PIPELINE WITH SECRET INJECTION"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

SCRIPT_DIR=$(dirname "$(realpath "$0")")
ARTIFACTS_DIR="$SCRIPT_DIR/../../artifacts"
PIPELINE_FILE="$ARTIFACTS_DIR/docling-rag-pipeline.yaml"

cd "$SCRIPT_DIR"

echo "Step 1: Compile base pipeline..."
source venv/bin/activate
python3 kfp/pipeline.py

if [ ! -s "$PIPELINE_FILE" ]; then
  echo "❌ Pipeline compilation failed or produced empty file"
  exit 1
fi

echo "✅ Base pipeline compiled"
echo ""

echo "Step 2: Inject Secret references..."

# Use Python to inject env vars with proper text manipulation
python3 <<'PYTHON_EOF'
import sys

yaml_file = "../../artifacts/docling-rag-pipeline.yaml"

with open(yaml_file, 'r') as f:
    content = f.read()

# Find the download-from-s3 executor container block
# Look for: "exec-download-from-s3:" then find its "container:" section
# Inject env vars right after "image:" line

lines = content.split('\n')
output_lines = []
injected = False

for i, line in enumerate(lines):
    output_lines.append(line)
    
    # Look for "comp-download-from-s3" in the executors section
    if 'comp-download-from-s3' in line and i + 5 < len(lines):
        # Find the container image line within next 20 lines
        for j in range(i, min(i + 30, len(lines))):
            if '        image:' in lines[j] and not injected:
                # Found the image line, inject env block
                output_lines = output_lines[:len(output_lines)]
                # Find position after image line
                insert_pos = len(output_lines)
                
                # Add env block
                env_block = [
                    '        env:',
                    '        - name: AWS_ACCESS_KEY_ID',
                    '          valueFrom:',
                    '            secretKeyRef:',
                    '              key: accesskey',
                    '              name: minio-storage-credentials',
                    '        - name: AWS_SECRET_ACCESS_KEY',
                    '          valueFrom:',
                    '            secretKeyRef:',
                    '              key: secretkey',
                    '              name: minio-storage-credentials'
                ]
                
                # Continue adding remaining lines but insert env after image
                for k in range(i+1, j+1):
                    if k < len(lines):
                        output_lines.append(lines[k])
                
                # Now inject env block
                output_lines.extend(env_block)
                injected = True
                
                # Skip the lines we already added
                for k in range(j+1, len(lines)):
                    output_lines.append(lines[k])
                
                print(f"✅ Injected env vars at line {j+1}")
                break
        
        if injected:
            break

if injected:
    with open(yaml_file, 'w') as f:
        f.write('\n'.join(output_lines))
    print("✅ YAML patched successfully")
else:
    print("⚠️  Could not find injection point, keeping original")

PYTHON_EOF

echo ""

echo "Step 3: Verify secret injection..."
if grep -q "secretKeyRef" "$PIPELINE_FILE"; then
  echo "✅ Secret references found in YAML"
  grep -A 3 "AWS_ACCESS_KEY_ID" "$PIPELINE_FILE" | head -6
else
  echo "⚠️  No secret references found - using compiled YAML as-is"
fi

echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "✅ PIPELINE READY: $PIPELINE_FILE"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

