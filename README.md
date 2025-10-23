# Red Hat AI Demo - Three-Stage Journey

**Complete demonstration of Red Hat AI's Four Pillars across hybrid cloud environments**

---

## 🚀 Quick Start

This demo showcases Red Hat AI capabilities through three progressive stages:

1. **Stage 1**: Sovereign AI with efficient inference
2. **Stage 2**: Private data enhancement with RAG & InstructLab  
3. **Stage 3**: Enterprise agentic AI with MCP servers

---

## 📁 Project Structure

```
llama-stack-tst-demo/
├── README.md                    # This file
├── gitops/                      # GitOps deployment (Kustomize)
│   ├── base/                    # Essential: namespace, vLLM
│   ├── components/              # Optional: GPUs, loaders, benchmarks
│   ├── overlays/                # Environments: dev, staging, production
│   ├── kustomization.yaml       # Root: deploy everything
│   └── README.md                # Deployment guide
├── stage1-sovereign-ai/         # Stage 1 (README.md + deploy.sh)
├── stage2-private-data-rag/     # Stage 2 (README.md + deploy.sh)
├── stage3-enterprise-mcp/       # Stage 3 (README.md + deploy.sh)
└── docs/                        # Reference documentation
    ├── presentations/           # Demo scripts & talking points
    └── reference/               # Architecture docs & guides
```

---

## 🎯 Prerequisites

- OpenShift cluster with admin access
- GPU nodes (or ability to provision via MachineSets)
- `oc` CLI configured
- HuggingFace token (for model downloads)
- Basic understanding of Kubernetes/OpenShift

---

## 📚 Stage Overview

### Stage 1: Sovereign AI (20 minutes)
**Focus**: Efficient inference + Hybrid cloud flexibility

**What you'll demonstrate**:
- Deploy models with 75% GPU cost savings (quantization)
- vLLM as inference engine
- Complete data sovereignty
- GitOps-based deployment

**Automated deployment**: `cd stage1-sovereign-ai && ./deploy.sh`  
**Manual guide**: [stage1-sovereign-ai/README.md](./stage1-sovereign-ai/README.md)

---

### Stage 2: Private Data Enhancement (30 minutes)
**Focus**: Data connection + Hybrid cloud flexibility

**What you'll demonstrate**:
- RAG for grounding LLM responses in your documents
- InstructLab for accessible model fine-tuning
- Vector databases and embeddings
- Data processed where it lives

**Automated deployment**: `cd stage2-private-data-rag && ./deploy.sh` (planned)  
**Manual guide**: [stage2-private-data-rag/README.md](./stage2-private-data-rag/README.md)

---

### Stage 3: Enterprise Agentic AI (30 minutes)
**Focus**: Agentic AI + Hybrid cloud flexibility

**What you'll demonstrate**:
- Model Context Protocol (MCP) for system integration
- Quarkus AI agents (enterprise Java)
- Autonomous multi-system workflows
- Production-ready architecture

**Automated deployment**: `cd stage3-enterprise-mcp && ./deploy.sh` (planned)  
**Manual guide**: [stage3-enterprise-mcp/README.md](./stage3-enterprise-mcp/README.md)

---

## 🏗️ GitOps Deployment

All infrastructure and applications are deployed via GitOps:

```bash
# Option 1: Deploy production (recommended)
oc apply -k gitops/overlays/production

# Option 2: Deploy development (for testing)
oc apply -k gitops/overlays/dev

# Option 3: Deploy step-by-step
oc apply -k gitops/base                    # Essential resources
oc apply -k gitops/components/model-loader # Download models
oc apply -k gitops/components/benchmarking # Run tests
```

See [gitops/README.md](./gitops/README.md) for details.

---

## 🎓 Red Hat AI Four Pillars

This demo demonstrates all Four Pillars:

**Pillar 3** (Foundation): Hybrid Cloud Flexibility
- Runs throughout all stages
- Deploy on-premise, cloud, edge, air-gapped
- Complete data sovereignty

**Pillar 1** (Stage 1): Efficient Inferencing
- vLLM optimization, 75% cost reduction
- Built ON Pillar 3

**Pillar 2** (Stage 2): Simplified Data Connection
- RAG and InstructLab
- Built ON Pillar 3

**Pillar 4** (Stage 3): Agentic AI Delivery
- MCP servers and Quarkus agents
- Built ON Pillar 3

See [docs/reference/FOUR-PILLARS-ALIGNMENT.md](./docs/reference/FOUR-PILLARS-ALIGNMENT.md) for details.

---

## 📖 Documentation

### For Demo Presenters
- [Demo Scripts](./docs/presentations/) - Complete presentation flows
- [Talking Points](./docs/presentations/) - Quick reference cards
- [Screenshots Guide](./docs/reference/screenshots/) - What to capture

### For Technical Implementation
- [GitOps Structure](./docs/reference/COMPLETE-STRUCTURE.md) - Full architecture
- [Deployment Guide](./docs/reference/DEPLOYMENT-GUIDE.md) - Step-by-step setup
- [Model Registry Guide](./docs/reference/MODEL-REGISTRY-METADATA-GUIDE.md) - Metadata setup

### For Architecture & Planning
- [Project Status](./docs/reference/PROJECT-STATUS.md) - Complete status & implementation guide
- [Four Pillars Alignment](./docs/reference/FOUR-PILLARS-ALIGNMENT.md) - Strategic framing
- [Project Summary](./docs/reference/PROJECT-SUMMARY.md) - Accomplishments

---

## 🎯 Demo Flow

**Recommended presentation order**:

1. **Introduction** (5 min)
   - AI Platform as Technology Decision Point
   - Big 3 challenges (Cost, Complexity, Flexibility)
   - Four Pillars overview

2. **Stage 1** (20 min)
   - Show efficient inference
   - Prove cost savings
   - Emphasize hybrid cloud deployment

3. **Stage 2** (30 min)
   - Demonstrate RAG
   - Show InstructLab workflow
   - Data sovereignty maintained

4. **Stage 3** (30 min)
   - Live agentic AI demo
   - Multi-system integration
   - Production considerations

5. **Conclusion** (5 min)
   - Recap Four Pillars
   - Customer examples
   - Next steps

**Total**: ~90 minutes (can be shortened to 60 min by cutting optional sections)

---

## ⚡ Quick Commands

```bash
# Verify cluster access
oc whoami
oc get nodes

# Check GPU nodes
oc get nodes -l nvidia.com/gpu.present=true

# Deploy Stage 1
oc apply -k gitops/overlays/production

# Check deployments
oc get inferenceservice -n private-ai-demo
oc get modelregistry -n model-registry

# Access dashboards
oc get route -n redhat-ods-applications
oc get route -n private-ai-demo
```

---

## 🆘 Troubleshooting

**Models not deploying?**
- Check GPU nodes: `oc get nodes -l nvidia.com/gpu.present=true`
- Check HuggingFace token: `oc get secret -n private-ai-demo`
- Check logs: `oc logs -n private-ai-demo <pod-name>`

**Dashboard not showing models?**
- Verify labels: `opendatahub.io/dashboard: "true"`
- Check Model Registry: `oc get modelregistry -n model-registry`
- Verify InferenceService: `oc get inferenceservice -n private-ai-demo -o yaml`

**For detailed troubleshooting**, see stage-specific README files.

---

## 🤝 Contributing

This demo is a living project. To improve:

1. Test in your environment
2. Document issues/improvements
3. Submit pull requests
4. Share customer feedback

---

## 📞 Support

- **Red Hat OpenShift AI**: https://www.redhat.com/en/technologies/cloud-computing/openshift/openshift-ai
- **Documentation**: https://docs.redhat.com/en/documentation/red_hat_openshift_ai
- **Community**: https://www.redhat.com/en/about/open-source

---

**Ready to start?** → [Stage 1: Sovereign AI](./stage1-sovereign-ai/README.md)
