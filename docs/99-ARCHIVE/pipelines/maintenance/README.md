# Pipeline Maintenance Scripts

This directory contains one-time maintenance and migration scripts for the Model Registry pipelines.

## Available Scripts

### 🔄 `cleanup-migrate-to-top24.yaml`

**Purpose:** Migrate existing model versions to TOP 24 property schema

**When to use:**
- After implementing TOP 24 property strategy
- To clean up models created with old schema (32 properties)
- To update `source` property from `"HuggingFace"` to full URL

**How to run:**

```bash
# Create the migration TaskRun
oc create -f cleanup-migrate-to-top24.yaml

# Monitor progress
TR=$(oc get taskrun -n private-ai-demo --sort-by=.metadata.creationTimestamp -o name | tail -1)
oc logs -n private-ai-demo ${TR##*/} -f

# Check results
oc logs -n private-ai-demo ${TR##*/} | tail -20
```

**Expected output:**

```
✅ MIGRATION COMPLETE
📊 Summary:
   Models processed:       2
   Versions migrated:      4
   Properties removed:     36
   Source URLs updated:    4

🎯 All model versions are now TOP 24 compliant!
```

**Safe to run multiple times** - Script is idempotent and won't duplicate work.

**What it does:**
1. Connects to Model Registry internal service
2. Fetches all registered models and their versions
3. For each version:
   - Removes properties not in TOP 24 list
   - Updates `source` from `"HuggingFace"` to `https://huggingface.co/...`
   - Preserves all TOP 24 properties unchanged
4. Updates only if changes are needed
5. Reports summary statistics

**Properties removed:**
- `pipeline` (confusing internal detail)
- `s3_prefix` (derivable from artifact_uri)
- `test_pipeline_run_uid` (redundant with run name)
- 4 stderr metrics (statistical details)
- `eval_hellaswag_alias` (redundant)

---

## Adding New Maintenance Scripts

When adding new maintenance scripts to this directory:

1. **Naming Convention:** `cleanup-<action>-<date>.yaml` or `maintenance-<action>.yaml`

2. **Required Labels:**
   ```yaml
   metadata:
     labels:
       maintenance: <category>
       version: <schema-version>
   ```

3. **Required Annotations:**
   ```yaml
   metadata:
     annotations:
       description: |
         Clear description of what this script does,
         when to use it, and any prerequisites.
   ```

4. **Documentation:**
   - Add entry to this README
   - Document in relevant guide under `docs/02-PIPELINES/`
   - Include example output

5. **Safety:**
   - Make scripts idempotent (safe to run multiple times)
   - Add dry-run option if modifying critical data
   - Log all changes for audit trail

---

## Related Documentation

- [TOP 24 Property Strategy](../../../../docs/02-PIPELINES/TOP-24-PROPERTY-STRATEGY.md) - Full documentation
- [Model Registry REST API Fix](../../../../docs/02-PIPELINES/MODEL-REGISTRY-REST-API-FIX.md) - API usage
- [Pipeline Structure](../../../../docs/01-ARCHITECTURE/PROJECT-STRUCTURE.md) - Overall layout

---

## Cleanup Schedule

### One-Time Migrations

| Script | Date Applied | Status | Models Affected |
|--------|--------------|--------|-----------------|
| `cleanup-migrate-to-top24.yaml` | 2025-10-31 | ✅ Ready | All existing |

### Periodic Maintenance

None currently scheduled. Add future recurring maintenance tasks here.

---

## Troubleshooting

### "Connection refused" errors

**Cause:** Model Registry service not accessible

**Fix:**
```bash
# Check service is running
oc get svc -n rhoai-model-registries private-ai-model-registry

# Verify pod is healthy
oc get pods -n rhoai-model-registries -l app=model-registry

# Test connectivity from namespace
oc run curl-test -n private-ai-demo --image=curlimages/curl:8.5.0 --rm -it -- \
  curl -s http://private-ai-model-registry.rhoai-model-registries.svc:8080/api/model_registry/v1alpha3/registered_models
```

### "No models found" but models exist

**Cause:** Querying wrong namespace or API endpoint

**Fix:**
```bash
# Verify API endpoint
curl http://private-ai-model-registry.rhoai-model-registries.svc:8080/api/model_registry/v1alpha3/registered_models

# Check via oc CLI
oc get taskrun -n private-ai-demo -l tekton.dev/pipeline=model-deployment
```

### Migration script doesn't remove properties

**Cause:** Properties already migrated or not in removal list

**Check logs:**
```bash
oc logs -n private-ai-demo <taskrun-name> | grep "No changes needed"
```

This is expected for models already compliant with TOP 24 schema.

---

## Contact

For issues or questions about maintenance scripts:

1. Check related documentation in `docs/02-PIPELINES/`
2. Review TaskRun logs for error details
3. Verify Model Registry service health
4. Consult [Model Registry documentation](https://github.com/opendatahub-io/model-registry)

