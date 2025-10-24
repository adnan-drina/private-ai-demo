# Stage 3 Demo Notebook

## 📓 ACME LithoOps Agent - Multi-Agent Orchestration Demo

This interactive Jupyter notebook demonstrates the ACME LithoOps Agent's multi-agent orchestration capabilities.

### 🎯 What It Shows

**Step-by-step breakdown of:**
1. Equipment metadata retrieval (Database MCP)
2. Calibration limits retrieval (RAG + Llama Stack)
3. Telemetry data analysis
4. LLM-powered expert analysis
5. Real-time Slack notifications

**At each step, you'll see:**
- ✅ What happens under the hood
- 💰 Business value delivered
- 🧠 How the LLM adds intelligence

### 📊 Business Value

- **Time:** 110 minutes → 20 seconds (99.7% reduction)
- **Cost:** $137.25 → $0.10 per check
- **Annual Savings:** $137,150 (1,000 checks/year)
- **Quality:** Consistent, error-free, 24/7

### 🚀 How to Use

1. **Prerequisites:**
   - Stage 1 deployed (vLLM models)
   - Stage 2 deployed (RAG system)
   - Stage 3 deployed (ACME Agent + MCP servers)

2. **Launch Jupyter:**
   ```bash
   # From OpenShift AI dashboard
   # Or from command line:
   jupyter notebook 01-acme-agent-demo.ipynb
   ```

3. **Run Cells:**
   - Execute cells in order
   - Change `telemetry_scenario` to see different outcomes:
     - `"clean"` - Equipment operating normally (PASS)
     - `"drift"` - Calibration drift detected (FAIL)

### 📚 Notebook Structure

| Cell | Description | Business Value |
|------|-------------|----------------|
| 1 | Setup & imports | - |
| 2 | Submit calibration request | Self-service, 24/7 |
| 3 | Equipment metadata (DB MCP) | Saves 15-20 min |
| 4 | Calibration limits (RAG) | Saves 20-30 min |
| 5 | Telemetry data & visualization | Saves 10 min |
| 6 | LLM analysis (THE MAGIC!) | Saves 30-45 min |
| 7 | Slack alert | Instant notification |
| 8 | Business value summary | ROI analysis |

### 🎨 Interactive Features

- ✅ Live API calls to MCP servers (when available)
- ✅ Data visualization with threshold lines
- ✅ LLM prompt inspection
- ✅ Side-by-side scenario comparison
- ✅ ROI calculator

### 💡 Key Messages

1. **Multi-Agent Orchestration** - Agent coordinates 4 systems automatically
2. **RAG Business Value** - Instant access to 500+ pages of documentation
3. **LLM as Domain Expert** - AI performs analysis at engineer level
4. **Enterprise Integration** - Seamless connection to DB, Slack, etc.
5. **Scalability** - Can handle 100s of checks simultaneously
6. **Consistency** - Same quality analysis every time

### 📖 Related Documentation

- **Flow Draft:** `../docs/NOTEBOOK-FLOW-DRAFT.md` - Detailed breakdown of each step
- **Validation Guide:** `../docs/VALIDATION-GUIDE.md` - How to validate the deployment
- **Stage 3 README:** `../README.md` - Complete Stage 3 overview

### 🔧 Troubleshooting

**Issue:** Can't connect to services
- **Solution:** Check that Stage 3 is deployed (`oc get pods -n acme-calibration-ops`)

**Issue:** 404 errors
- **Solution:** Update service URLs in Cell 1 to match your cluster

**Issue:** No telemetry data
- **Solution:** CSV files are embedded in the notebook, no external files needed

---

**Ready to see enterprise agentic AI in action?** Run the notebook! 🚀
