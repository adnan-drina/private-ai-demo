#!/bin/bash
#
# Upload files to MinIO for RAG ingestion pipeline
# Usage: ./upload-to-minio.sh <local-file-path> <destination-s3-path>
# Example: ./upload-to-minio.sh ~/document.pdf s3://llama-files/sample/document.pdf
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-private-ai-demo}"

# Check arguments
if [ $# -lt 2 ]; then
  echo -e "${RED}Usage: $0 <local-file-path> <s3-destination>${NC}"
  echo ""
  echo "Example:"
  echo "  $0 ~/acme-policy.pdf s3://llama-files/sample/acme-policy.pdf"
  echo ""
  exit 1
fi

LOCAL_FILE="$1"
S3_DEST="$2"

# Validate local file exists
if [ ! -f "$LOCAL_FILE" ]; then
  echo -e "${RED}❌ File not found: $LOCAL_FILE${NC}"
  exit 1
fi

# Parse S3 destination
if [[ ! "$S3_DEST" =~ ^s3://([^/]+)/(.+)$ ]]; then
  echo -e "${RED}❌ Invalid S3 destination: $S3_DEST${NC}"
  echo "Format: s3://bucket-name/path/to/file"
  exit 1
fi

BUCKET="${BASH_REMATCH[1]}"
KEY="${BASH_REMATCH[2]}"

echo "════════════════════════════════════════════════════════════════════════════════"
echo "📤 UPLOADING FILE TO MINIO"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Local file:   $LOCAL_FILE ($(stat -f%z "$LOCAL_FILE" 2>/dev/null || stat -c%s "$LOCAL_FILE") bytes)"
echo "Bucket:       $BUCKET"
echo "Key:          $KEY"
echo "Namespace:    $NAMESPACE"
echo ""

# Get MinIO credentials
echo "Retrieving MinIO credentials..."
MINIO_KEY=$(oc -n model-storage get secret minio-credentials -o jsonpath='{.data.accesskey}' | base64 -d)
MINIO_SECRET=$(oc -n model-storage get secret minio-credentials -o jsonpath='{.data.secretkey}' | base64 -d)

if [ -z "$MINIO_KEY" ] || [ -z "$MINIO_SECRET" ]; then
  echo -e "${RED}❌ Failed to retrieve MinIO credentials${NC}"
  exit 1
fi

echo -e "${GREEN}✅ MinIO credentials retrieved${NC}"
echo ""

# Create temporary upload pod
echo "Creating temporary upload pod..."

POD_NAME="minio-uploader-$(date +%s)"

oc -n "$NAMESPACE" run "$POD_NAME" --rm -i --restart=Never \
  --env=HOME=/tmp \
  --env=AK="$MINIO_KEY" \
  --env=SK="$MINIO_SECRET" \
  --env=ENDPOINT="http://minio.model-storage.svc:9000" \
  --env=BUCKET="$BUCKET" \
  --env=KEY="$KEY" \
  --image=registry.access.redhat.com/ubi9/ubi:latest \
  --command -- /bin/bash -c '
set -e

# Install mc
echo "Installing MinIO client..."
curl -sL https://dl.min.io/client/mc/release/linux-amd64/mc -o /tmp/mc
chmod +x /tmp/mc

# Configure alias
echo "Configuring MinIO alias..."
/tmp/mc alias set minio "$ENDPOINT" "$AK" "$SK"

# Create bucket if needed
echo "Ensuring bucket exists..."
/tmp/mc mb -p minio/"$BUCKET" || true

# Wait for file to be piped in
echo "Waiting for file content..."
cat > /tmp/upload-file

# Upload file
echo "Uploading to MinIO..."
/tmp/mc cp /tmp/upload-file minio/"$BUCKET"/"$KEY"

# Verify
echo "Verifying upload..."
/tmp/mc stat minio/"$BUCKET"/"$KEY"

echo ""
echo "✅ Upload complete!"
' < "$LOCAL_FILE"

echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo -e "${GREEN}✅ FILE UPLOADED SUCCESSFULLY${NC}"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "S3 URI: $S3_DEST"
echo ""
echo "Verify with:"
echo "  oc -n $NAMESPACE run mc-test --rm -i --restart=Never --image=quay.io/minio/mc -- \\"
echo "    mc --insecure alias set minio http://minio.model-storage.svc:9000 $MINIO_KEY $MINIO_SECRET && \\"
echo "    mc --insecure stat minio/$BUCKET/$KEY"
echo ""

