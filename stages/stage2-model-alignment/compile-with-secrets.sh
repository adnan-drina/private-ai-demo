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

echo "Step 2: Inject Secret volume mounts (avoiding KFP v2 env stripping)..."

# Use sed to inject volumes and volumeMounts
# This avoids KFP v2's secretKeyRef stripping in env vars

# Find the exec-download-from-s3 section and inject volume mount + volume definition
cat > /tmp/inject-volume-mounts.sh <<'INJECT_SCRIPT'
#!/bin/bash

YAML_FILE="$1"

# Find line number of exec-download-from-s3 container
EXEC_LINE=$(grep -n "exec-download-from-s3:" "$YAML_FILE" | head -1 | cut -d: -f1)

if [ -z "$EXEC_LINE" ]; then
  echo "❌ Could not find exec-download-from-s3"
  exit 1
fi

echo "Found exec-download-from-s3 at line $EXEC_LINE"

# Find the container: line after exec-download-from-s3
CONTAINER_LINE=$(awk -v start=$EXEC_LINE 'NR > start && /^      container:/ {print NR; exit}' "$YAML_FILE")

if [ -z "$CONTAINER_LINE" ]; then
  echo "❌ Could not find container section"
  exit 1
fi

echo "Found container at line $CONTAINER_LINE"

# Inject volumeMounts right after container: line
sed -i.bak "${CONTAINER_LINE}a\\
        volumeMounts:\\
        - name: minio-cred\\
          mountPath: /var/secrets/minio\\
          readOnly: true
" "$YAML_FILE"

echo "✅ Injected volumeMounts"

# Now find the end of the exec-download-from-s3 section (next exec- or end of executors)
# and inject volumes definition at the podSpec level

# Find the line with the next executor or deploymentSpec closing
NEXT_EXEC_LINE=$(awk -v start=$EXEC_LINE 'NR > start && /^    exec-[a-z]/ {print NR; exit}' "$YAML_FILE")

if [ -z "$NEXT_EXEC_LINE" ]; then
  # If no next executor, find the end of deploymentSpec.executors
  NEXT_EXEC_LINE=$(awk -v start=$EXEC_LINE 'NR > start && /^  [a-z]/ {print NR; exit}' "$YAML_FILE")
fi

if [ -z "$NEXT_EXEC_LINE" ]; then
  echo "⚠️  Could not find injection point for volumes, skipping"
else
  # Inject volumes definition before the next section
  INSERT_LINE=$((NEXT_EXEC_LINE - 1))
  sed -i.bak2 "${INSERT_LINE}a\\
      volumes:\\
      - name: minio-cred\\
        secret:\\
          secretName: dspa-minio-credentials
" "$YAML_FILE"
  
  echo "✅ Injected volumes definition at line $INSERT_LINE"
fi

rm -f "$YAML_FILE.bak" "$YAML_FILE.bak2"
INJECT_SCRIPT

chmod +x /tmp/inject-volume-mounts.sh
/tmp/inject-volume-mounts.sh "$PIPELINE_FILE"
rm /tmp/inject-volume-mounts.sh

echo ""

echo "Step 3: Verify volume mount injection..."
if grep -q "volumeMounts:" "$PIPELINE_FILE" && grep -q "minio-cred" "$PIPELINE_FILE"; then
  echo "✅ Volume mounts found in YAML"
  echo ""
  echo "volumeMounts:"
  grep -A 3 "volumeMounts:" "$PIPELINE_FILE" | head -5
  echo ""
  echo "volumes:"
  grep -A 3 "volumes:" "$PIPELINE_FILE" | grep -A 3 "minio-cred" | head -5
else
  echo "⚠️  No volume mounts found - using compiled YAML as-is"
fi

echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "✅ PIPELINE READY: $PIPELINE_FILE"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

