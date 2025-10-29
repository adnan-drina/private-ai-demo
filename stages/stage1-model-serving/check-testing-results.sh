#!/bin/bash
# Check Model Testing Pipeline Results
# Compares custom properties before/after testing pipeline

set -e

MR_HOST="http://$(oc get route private-ai-model-registry-http -n rhoai-model-registries -o jsonpath='{.spec.host}')"
VERSION_ID="5"  # quantized-w4a16-2501

echo "═══════════════════════════════════════════════════════════════════"
echo "📊 Model Testing Pipeline - Results Validation"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Model: Mistral-Small-24B-Instruct"
echo "Version: quantized-w4a16-2501"
echo "Version ID: ${VERSION_ID}"
echo ""
echo "───────────────────────────────────────────────────────────────────"
echo ""

# Get current properties
echo "🔍 Fetching current custom properties..."
DATA=$(curl -sk "${MR_HOST}/api/model_registry/v1alpha3/model_versions/${VERSION_ID}")

# Count properties
TOTAL=$(echo "$DATA" | jq '.customProperties | keys | length')
EVAL=$(echo "$DATA" | jq '.customProperties | keys | map(select(startswith("eval_"))) | length')
BENCH=$(echo "$DATA" | jq '.customProperties | keys | map(select(startswith("benchmark_"))) | length')
BUILD=$((TOTAL - EVAL - BENCH))

echo "✅ Properties Retrieved!"
echo ""
echo "───────────────────────────────────────────────────────────────────"
echo "📈 PROPERTY COUNTS:"
echo "───────────────────────────────────────────────────────────────────"
echo ""
printf "  %-30s %3d\n" "Total Properties:" "$TOTAL"
printf "  %-30s %3d\n" "Build/Deployment Metadata:" "$BUILD"
printf "  %-30s %3d %s\n" "Evaluation (eval_*):" "$EVAL" "$([ $EVAL -eq 0 ] && echo "❌" || echo "✅")"
printf "  %-30s %3d %s\n" "Benchmark (benchmark_*):" "$BENCH" "$([ $BENCH -eq 0 ] && echo "❌" || echo "✅")"
echo ""
echo "───────────────────────────────────────────────────────────────────"
echo "📊 COMPARISON TO BASELINE:"
echo "───────────────────────────────────────────────────────────────────"
echo ""

BASELINE_TOTAL=11
BASELINE_EVAL=0
BASELINE_BENCH=0

EXPECTED_TOTAL=26
EXPECTED_EVAL=6
EXPECTED_BENCH=9

printf "  %-20s %8s %8s %8s\n" "Property Type" "Baseline" "Current" "Expected"
printf "  %-20s %8s %8s %8s\n" "────────────────────" "────────" "────────" "────────"
printf "  %-20s %8d %8d %8d %s\n" "Total" "$BASELINE_TOTAL" "$TOTAL" "$EXPECTED_TOTAL" "$([ $TOTAL -ge $EXPECTED_TOTAL ] && echo "✅" || echo "⏳")"
printf "  %-20s %8d %8d %8d %s\n" "Evaluation" "$BASELINE_EVAL" "$EVAL" "$EXPECTED_EVAL" "$([ $EVAL -ge $EXPECTED_EVAL ] && echo "✅" || echo "⏳")"
printf "  %-20s %8d %8d %8d %s\n" "Benchmark" "$BASELINE_BENCH" "$BENCH" "$EXPECTED_BENCH" "$([ $BENCH -ge $EXPECTED_BENCH ] && echo "✅" || echo "⏳")"
echo ""

# Status determination
if [ "$EVAL" -ge "$EXPECTED_EVAL" ] && [ "$BENCH" -ge "$EXPECTED_BENCH" ]; then
  STATUS="✅ COMPLETE"
  STATUS_MSG="Testing pipeline has successfully completed!"
  echo "───────────────────────────────────────────────────────────────────"
  echo "✅ VALIDATION: PASSED"
  echo "───────────────────────────────────────────────────────────────────"
  echo ""
  echo "  ✅ All expected evaluation properties present"
  echo "  ✅ All expected benchmark properties present"
  echo "  ✅ Testing results published to Model Registry"
  echo ""
elif [ "$EVAL" -gt 0 ] || [ "$BENCH" -gt 0 ]; then
  STATUS="⏳ PARTIAL"
  STATUS_MSG="Testing pipeline is in progress (some results available)"
  echo "───────────────────────────────────────────────────────────────────"
  echo "⏳ VALIDATION: IN PROGRESS"
  echo "───────────────────────────────────────────────────────────────────"
  echo ""
  [ "$EVAL" -gt 0 ] && echo "  ✅ Evaluation results available"
  [ "$EVAL" -eq 0 ] && echo "  ⏳ Waiting for evaluation results..."
  [ "$BENCH" -gt 0 ] && echo "  ✅ Benchmark results available"
  [ "$BENCH" -eq 0 ] && echo "  ⏳ Waiting for benchmark results..."
  echo ""
else
  STATUS="⏳ PENDING"
  STATUS_MSG="Testing pipeline has not started or is still running"
  echo "───────────────────────────────────────────────────────────────────"
  echo "⏳ VALIDATION: PENDING"
  echo "───────────────────────────────────────────────────────────────────"
  echo ""
  echo "  ⏳ No testing results available yet"
  echo "  ⏳ Pipeline may still be running"
  echo ""
fi

# Show detailed properties if testing is complete
if [ "$EVAL" -ge "$EXPECTED_EVAL" ] && [ "$BENCH" -ge "$EXPECTED_BENCH" ]; then
  echo "───────────────────────────────────────────────────────────────────"
  echo "📋 EVALUATION RESULTS:"
  echo "───────────────────────────────────────────────────────────────────"
  echo ""
  echo "$DATA" | jq -r '.customProperties | to_entries | map(select(.key | startswith("eval_"))) | sort_by(.key) | .[] | "  \(.key): \(.value.string_value // .value)"'
  echo ""
  echo "───────────────────────────────────────────────────────────────────"
  echo "📋 BENCHMARK RESULTS:"
  echo "───────────────────────────────────────────────────────────────────"
  echo ""
  echo "$DATA" | jq -r '.customProperties | to_entries | map(select(.key | startswith("benchmark_"))) | sort_by(.key) | .[] | "  \(.key): \(.value.string_value // .value)"'
  echo ""
fi

echo "───────────────────────────────────────────────────────────────────"
echo "🎯 SUMMARY:"
echo "───────────────────────────────────────────────────────────────────"
echo ""
echo "  Status: ${STATUS}"
echo "  ${STATUS_MSG}"
echo ""

# Exit with appropriate code
if [ "$EVAL" -ge "$EXPECTED_EVAL" ] && [ "$BENCH" -ge "$EXPECTED_BENCH" ]; then
  echo "  ✅ Validation successful! All testing metrics published."
  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  exit 0
else
  echo "  ⏳ Testing still in progress. Run this script again later."
  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  exit 1
fi

