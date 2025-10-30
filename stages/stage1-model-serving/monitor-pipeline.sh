#!/usr/bin/env bash
set -euo pipefail

# Robust Tekton PipelineRun monitor for OpenShift
# - Streams key step logs (download, upload-to-minio, build-runtime-image, register-model)
# - Prints TaskRun failure reason and last logs automatically
# - Shows relevant pod events on failures (e.g., storage pressure, mount errors)
# Usage:
#   ./monitor-pipeline.sh -n <namespace> -r <pipelinerun-name>

NS=""
PR=""
while getopts ":n:r:" opt; do
  case "$opt" in
    n) NS="$OPTARG" ;;
    r) PR="$OPTARG" ;;
    *) echo "Usage: $0 -n <namespace> -r <pipelinerun>" >&2; exit 2 ;;
  esac
done

if [[ -z "${NS}" || -z "${PR}" ]]; then
  echo "Usage: $0 -n <namespace> -r <pipelinerun>" >&2
  exit 2
fi

echo "Monitoring PipelineRun: ${PR} (namespace: ${NS})"

step_to_container() {
  case "$1" in
    download-model|download-model-v2) echo step-download-model ;;
    upload-to-minio) echo step-upload-to-minio ;;
    build-runtime-image) echo step-build-runtime ;;
    register-model) echo step-register-via-sdk ;;
    *) echo "" ;;
  esac
}

print_failure_debug() {
  local tr="$1"
  local pod
  pod=$(oc get pod -n "$NS" -l tekton.dev/taskRun="$tr" -o name 2>/dev/null | head -1)
  echo "--- TaskRun $tr status ---"
  oc get taskrun -n "$NS" "$tr" -o jsonpath='{.status.conditions[0].reason}{"\t"}{.status.conditions[0].message}{"\n"}' || true
  if [[ -n "$pod" ]]; then
    pod=${pod#pod/}
    echo "--- Pod events ($pod) ---"
    oc get events -n "$NS" --field-selector involvedObject.name="$pod" --sort-by=.lastTimestamp | tail -n 30 || true
    echo "--- Pod describe (tail) ---"
    oc describe pod -n "$NS" "$pod" | tail -n 120 || true
  fi
}

wait_and_stream_task() {
  local task_name="$1"
  local container
  container=$(step_to_container "$task_name")
  [[ -z "$container" ]] && return 0

  local tr
  # Find the TaskRun for this pipeline task
  for i in {1..120}; do
    tr=$(oc get taskrun -n "$NS" -l tekton.dev/pipelineRun="$PR" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.tekton\.dev/pipelineTask}{"\n"}{end}' \
        | awk -v t="$task_name" '$2==t{print $1}' | tail -1)
    [[ -n "$tr" ]] && break
    sleep 2
  done
  [[ -z "$tr" ]] && { echo "[$task_name] TaskRun not found"; return 1; }

  echo "[$task_name] TaskRun: $tr"

  local pod
  for i in {1..120}; do
    pod=$(oc get pod -n "$NS" -l tekton.dev/taskRun="$tr" -o name 2>/dev/null | head -1)
    [[ -n "$pod" ]] && break
    sleep 2
  done

  if [[ -z "$pod" ]]; then
    echo "[$task_name] Pod not created"
    print_failure_debug "$tr"
    return 1
  fi

  pod=${pod#pod/}
  echo "[$task_name] Streaming logs from $pod ($container)"
  # Stream logs until container finishes
  oc logs -n "$NS" "$pod" -c "$container" -f || true

  # Check success/failure and surface errors
  local reason status
  reason=$(oc get taskrun -n "$NS" "$tr" -o jsonpath='{.status.conditions[0].reason}' || true)
  status=$(oc get taskrun -n "$NS" "$tr" -o jsonpath='{.status.conditions[0].status}' || true)
  if [[ "$status" != "True" ]]; then
    echo "[$task_name] FAILED ($reason)"
    print_failure_debug "$tr"
    return 1
  fi
  echo "[$task_name] Succeeded"
}

# Stream in order; exit non-zero on first failure
tasks=(download-model upload-to-minio build-runtime-image register-model)
for t in "${tasks[@]}"; do
  wait_and_stream_task "$t" || exit 1
done

echo "PipelineRun $PR: all monitored tasks completed"

