# Stage 2 Notebooks

## Structure

```
notebooks/
├── README.md                          # This file
├── templates/                         # Template notebooks with placeholders
│   ├── 02-rag-demo-redhat.ipynb.template
│   ├── 03-rag-demo-eu-ai-act.ipynb.template
│   └── 04-rag-demo-acme-litho.ipynb.template
├── 02-rag-demo-redhat.ipynb          # Generated (do not edit directly)
├── 03-rag-demo-eu-ai-act.ipynb       # Generated (do not edit directly)
└── 04-rag-demo-acme-litho.ipynb      # Generated (do not edit directly)
```

## Dynamic URL Injection

The notebooks use **dynamic URL injection** to work on any cluster.

### Template Placeholders

Templates use these placeholders:
- `${VLLM_URL}` - vLLM InferenceService URL (external route)
- `${LLAMASTACK_URL}` - Llama Stack internal service URL

### How It Works

1. **Templates** (`.ipynb.template`):
   - Source of truth for notebook content
   - Contain placeholders instead of hardcoded URLs
   - Stored in `templates/` directory

2. **Generation** (during `deploy.sh`):
   - `deploy.sh` fetches actual cluster URLs
   - Uses `envsubst` to replace placeholders
   - Generates final `.ipynb` files
   - Creates ConfigMaps with generated content

3. **Deployment**:
   - ConfigMaps applied to cluster
   - Notebooks mounted in JupyterLab workbench
   - Always have correct URLs for current cluster

### URL Sources

```bash
# vLLM URL (external route)
VLLM_URL=$(oc get inferenceservice mistral-24b-quantized \
  -n private-ai-demo -o jsonpath='{.status.url}')/v1

# Llama Stack URL (internal service)
LLAMASTACK_URL=http://llamastack.private-ai-demo.svc.cluster.local:8000
```

### Making Changes

**To update notebook content:**

1. Edit the **template** file in `templates/`
2. Run `deploy.sh` to regenerate notebooks
3. Notebooks will be created with current cluster URLs

**Do NOT edit the `.ipynb` files directly** - they are generated!

### Benefits

✅ **Portable** - Works on any OpenShift cluster  
✅ **Reproducible** - No manual URL updates needed  
✅ **Maintainable** - Single source of truth (templates)  
✅ **Automatic** - URLs injected during deployment  

---

## Notebooks

### 1. Red Hat OpenShift AI Documentation
**File:** `02-rag-demo-redhat.ipynb`  
**Collection:** `redhat-docs`  
**Purpose:** Query Red Hat official documentation

### 2. EU AI Act Regulation
**File:** `03-rag-demo-eu-ai-act.ipynb`  
**Collection:** `eu-ai-act-docs`  
**Purpose:** Legal/compliance queries

### 3. ACME LithoOps Copilot
**File:** `04-rag-demo-acme-litho.ipynb`  
**Collection:** `acme-manufacturing`  
**Purpose:** Manufacturing procedures queries

---

*For deployment details, see `stage2-private-data-rag/README.md`*
