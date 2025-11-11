#!/bin/bash
set -euo pipefail

##############################################################################
# Stage 3: Model Monitoring with TrustyAI + OpenTelemetry + Llama Stack
#
# Deploys:
#   - TrustyAI LMEvalJobs (model quality evaluation)
#   - Grafana dashboards (performance + quality metrics)
#   - Prometheus ServiceMonitors (vLLM + Llama Stack)
#   - OpenTelemetry Collector
#   - Evaluation results notebook
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
GITOPS_PATH="${PROJECT_ROOT}/gitops/stage03-model-monitoring"
ENV_FILE="${PROJECT_ROOT}/.env"

echo "════════════════════════════════════════════════════════════════"
echo "  Stage 3: Model Monitoring"
echo "════════════════════════════════════════════════════════════════"
echo ""

if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

PROJECT_NAME="${PROJECT_NAME:-private-ai-demo}"
MINIO_ENDPOINT="${MINIO_ENDPOINT:-minio.model-storage.svc.cluster.local:9000}"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-}"
MINIO_BUCKET_TEMPO="${TEMPO_BUCKET:-tempo-traces}"
MINIO_BUCKET_GUIDELLM="${GUIDELLM_BUCKET:-guidellm-results}"

if [ -z "$MINIO_ACCESS_KEY" ] || [ -z "$MINIO_SECRET_KEY" ]; then
  MINIO_ACCESS_KEY=$(oc -n model-storage get secret minio-credentials -o jsonpath='{.data.accesskey}' 2>/dev/null | base64 -d || true)
  MINIO_SECRET_KEY=$(oc -n model-storage get secret minio-credentials -o jsonpath='{.data.secretkey}' 2>/dev/null | base64 -d || true)
fi

if [ -z "$MINIO_ACCESS_KEY" ] || [ -z "$MINIO_SECRET_KEY" ]; then
  echo "❌ MinIO credentials were not found (set MINIO_ACCESS_KEY / MINIO_SECRET_KEY in .env)."
  exit 1
fi

if [[ "$MINIO_ENDPOINT" =~ ^https?:// ]]; then
  MINIO_URL="$MINIO_ENDPOINT"
else
  MINIO_URL="http://${MINIO_ENDPOINT}"
fi

echo "📦 Ensuring MinIO bucket '${MINIO_BUCKET_TEMPO}' exists..."
oc -n "${PROJECT_NAME}" run tempo-mc --rm -i --restart=Never \
  --image=quay.io/minio/mc --env=HOME=/tmp \
  --command -- /bin/sh -c "
    mc alias set tempo ${MINIO_URL} ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY} --api S3v4 >/dev/null 2>&1 &&
    mc mb tempo/${MINIO_BUCKET_TEMPO} --ignore-existing >/dev/null 2>&1" >/dev/null 2>&1 || {
      echo "⚠️  Unable to create bucket '${MINIO_BUCKET_TEMPO}'. Confirm it exists on ${MINIO_URL}."
    }

echo "📦 Ensuring MinIO bucket '${MINIO_BUCKET_GUIDELLM}' exists for GuideLLM results..."
oc -n "${PROJECT_NAME}" run guidellm-mc --rm -i --restart=Never \
  --image=quay.io/minio/mc --env=HOME=/tmp \
  --command -- /bin/sh -c "
    mc alias set minio ${MINIO_URL} ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY} --api S3v4 >/dev/null 2>&1 &&
    mc mb minio/${MINIO_BUCKET_GUIDELLM} --ignore-existing >/dev/null 2>&1 &&
    mc mb minio/${MINIO_BUCKET_GUIDELLM}/daily --ignore-existing >/dev/null 2>&1 &&
    mc mb minio/${MINIO_BUCKET_GUIDELLM}/weekly --ignore-existing >/dev/null 2>&1" >/dev/null 2>&1 || {
      echo "⚠️  Unable to create bucket '${MINIO_BUCKET_GUIDELLM}'. Confirm it exists on ${MINIO_URL}."
    }
echo "   ✅ GuideLLM bucket ready: ${MINIO_BUCKET_GUIDELLM}"

OPERATORS_PATH="${GITOPS_PATH}/operators"
OBSERVABILITY_PATH="${GITOPS_PATH}/observability"
TRUSTYAI_PATH="${GITOPS_PATH}/trustyai"
NOTEBOOKS_PATH="${GITOPS_PATH}/notebooks"
TRUSTYAI_NS="redhat-ods-applications"

wait_for_resource() {
  local resource="$1"
  local checker="$2" # command to evaluate
  local tries=0
  local max_tries=60
  while ! eval "$checker" >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -ge "$max_tries" ]; then
      echo "❌ Timeout waiting for ${resource}"
      echo "   Check operator status with:"
      echo "     oc get csv -A | grep -E 'Grafana|Tempo|OpenTelemetry'"
      echo "   Re-run this script once the operator report has the CRD registered."
      return 1
    fi
    if (( tries % 6 == 0 )); then
      echo "   … still waiting for ${resource} (attempt ${tries}/${max_tries})"
    fi
    sleep 5
  done
  echo "   ✅ Available: ${resource}"
}

echo "📦 Ensuring operator namespaces and subscriptions..."
oc apply -k "$OPERATORS_PATH"

if [ -n "$MINIO_ACCESS_KEY" ] && [ -n "$MINIO_SECRET_KEY" ]; then
  echo ""
  echo "📦 Applying Tempo object storage secret..."
  TEMPO_ENDPOINT="http://${MINIO_ENDPOINT}"
  cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: tempo-storage
  namespace: ${PROJECT_NAME}
type: Opaque
stringData:
  bucket: ${MINIO_BUCKET_TEMPO}
  endpoint: ${MINIO_URL}
  access_key_id: ${MINIO_ACCESS_KEY}
  access_key_secret: ${MINIO_SECRET_KEY}
  insecure: "true"
EOF
fi

echo ""
echo "⏳ Waiting for operator CRDs to register..."
wait_for_resource "Grafana APIService" "oc get apiservice v1beta1.grafana.integreatly.org"
wait_for_resource "OpenTelemetryCollector CRD" "oc get crd opentelemetrycollectors.opentelemetry.io"
wait_for_resource "TempoStack CRD" "oc get crd tempostacks.tempo.grafana.com"

echo ""
echo "📦 Applying TrustyAI resources..."
oc apply -k "$TRUSTYAI_PATH"

echo ""
echo "🔄 Restarting TrustyAI operator to pick up configuration changes..."
oc delete pod -n "$TRUSTYAI_NS" \
  -l control-plane=trustyai-service-operator-controller-manager --ignore-not-found >/dev/null 2>&1 || true
wait_for_resource "TrustyAI operator" \
  "oc get pod -n \"$TRUSTYAI_NS\" -l control-plane=trustyai-service-operator-controller-manager --field-selector=status.phase=Running"

echo ""
echo "📦 Applying observability stack..."
oc apply -k "$OBSERVABILITY_PATH"

echo ""
echo "📦 Applying notebooks..."
oc apply -k "$NOTEBOOKS_PATH"

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Next steps:"
echo "  ./validate.sh                    - Check deployment status"
echo "  oc get lmevaljob                 - View evaluation jobs"
echo "  oc get route grafana             - Access Grafana dashboard"
