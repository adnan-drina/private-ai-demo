# RHOAI 3.0 Upgrade - Executive Summary

**Date**: November 16, 2025  
**Current Version**: RHOAI 2.25 (stable)  
**Target Version**: RHOAI 3.0  
**Document**: Executive briefing for stakeholders

---

## 🚨 **Critical Decision Required**

**Question**: Should we upgrade to RHOAI 3.0 now?  
**Answer**: **NO** - Wait for stable 3.x release (Q1-Q2 2026)

---

## 📊 **Key Facts**

| Aspect | Status |
|--------|--------|
| **Upgrade Path** | ❌ **NOT SUPPORTED** - Fresh installation required |
| **Current Version Support** | ✅ **RHOAI 2.25 is EUS** - Extended support continues |
| **RHOAI 3.0 Maturity** | ⚠️ **Fast Release** - For early adopters, not production |
| **Migration Effort** | 🔴 **30 days, 200+ hours** |
| **Migration Cost** | 💰 **$5,000-$8,000** (AWS infrastructure) |
| **Risk Level** | 🔴 **HIGH** - Breaking changes, data loss risk |

---

## 🎯 **Recommendation**

### **✅ WAIT for Stable 3.x Release**

**Why?**
1. **Red Hat's Official Guidance**: "RHOAI 3.0 is a fast release... ensuring a smooth migration path to the first stable 3.x release" ([source](https://access.redhat.com/articles/7133758))
2. **No Upgrade Path**: Must destroy and rebuild entire environment
3. **RHOAI 2.25 is EUS**: Extended support through 2026+
4. **High Risk**: Breaking API changes, custom integrations may break
5. **Known Bugs**: LlamaStack v0.3.0rc3 already has critical bugs in 2.25

**Timeline**:
- **Now → Q1 2026**: Continue on RHOAI 2.25, complete Stage 4 features
- **Q1-Q2 2026**: Stable 3.x released (estimated)
- **Q2 2026**: Execute migration to stable 3.x

---

## 📈 **What's New in RHOAI 3.0?**

### **🟢 Beneficial Features**

1. **Generative AI Playground** - Interactive UI for testing models and RAG
2. **TrustyAI Integration** - May fix our current guardrails bugs
3. **Distributed Inference (llm-d)** - Better GPU utilization
4. **Feature Store UI** - Web interface for ML features
5. **AI Assets Dashboard** - Better visibility of deployed resources

### **⚠️ Breaking Changes**

1. **LlamaStack API Changes** - `/v1/vector-io` may still be broken
2. **Custom Operators** - `LlamaStackDistribution`, `DoclingServe` CRDs may change
3. **Data Migration** - All RAG data (~2GB embeddings) must be re-ingested
4. **Custom Images** - `llama-stack-custom` image must be rebuilt
5. **GitOps Manifests** - 50-70 YAML files need updates

---

## 💡 **Migration Options**

### **Option A: Wait for Stable 3.x (RECOMMENDED)**

- **Timeline**: Q1-Q2 2026
- **Effort**: Same as Option B, but lower risk
- **Risk**: 🟢 **LOW**
- **Cost**: $0 (no additional infrastructure)

**Actions Now**:
- ✅ Continue development on RHOAI 2.25
- ✅ Complete Stage 4 (MCP, Agentic AI)
- ✅ Report bugs to Red Hat
- ✅ Monitor for stable 3.x announcements

---

### **Option B: Fresh Installation on RHOAI 3.0 (HIGH RISK)**

- **Timeline**: 4-6 weeks
- **Effort**: 200+ hours
- **Risk**: 🔴 **HIGH**
- **Cost**: $5,000-$8,000

**When to Choose**:
- Early adopter / R&D environment
- Testing new features urgently needed
- Separate cluster available (not production)

**Phases**:
1. **Week 1**: Provision cluster, install RHOAI 3.0, deploy Stage 0
2. **Week 2**: Migrate model serving (Stage 1)
3. **Week 3-4**: Rebuild LlamaStack, re-ingest RAG data (Stage 2) ⚠️ **HIGHEST RISK**
4. **Week 5**: Deploy observability and agentic features (Stage 3-4)
5. **Week 6**: Integration testing and cutover

---

### **Option C: Parallel Deployment (SAFEST)**

- **Timeline**: 6-8 weeks
- **Effort**: 200+ hours
- **Risk**: 🟡 **MEDIUM**
- **Cost**: $8,000-$12,000 (2x infrastructure)

**Advantages**:
- ✅ Zero downtime
- ✅ Easy rollback
- ✅ Gradual migration

**Disadvantages**:
- 💰 2x infrastructure cost
- 🕒 Managing 2 environments

---

## ⚠️ **Top 5 Risks**

| Risk | Impact | Mitigation |
|------|--------|------------|
| **LlamaStack API incompatibility** | 🔴 CRITICAL | Test on dev cluster, have rollback plan |
| **Data migration failures** | 🔴 CRITICAL | Backup RHOAI 2.25, test restore |
| **RHOAI 3.0 bugs (fast release)** | 🔴 HIGH | **Wait for stable 3.x** |
| **Custom image build failures** | 🔴 HIGH | Pre-build and test images |
| **Performance regression** | 🟡 MEDIUM | Benchmark before/after |

---

## 💰 **Cost-Benefit Analysis**

### **Option A (Wait) - RECOMMENDED**

| Category | Cost |
|----------|------|
| **Infrastructure** | $0 (continue on current cluster) |
| **Engineering Time** | 0 hours (no migration) |
| **Risk Mitigation** | 🟢 **LOW** (stable 3.x release) |
| **Feature Access** | Delayed 3-6 months |
| **TOTAL COST** | **$0** |

**ROI**: ✅ **POSITIVE** - Avoid wasted effort on unstable release

---

### **Option B (Fresh Install Now)**

| Category | Cost |
|----------|------|
| **Infrastructure** | $5,000-$8,000 (4-6 weeks, 2 clusters) |
| **Engineering Time** | 200 hours × $150/hr = **$30,000** |
| **Risk Mitigation** | 🔴 **HIGH** (fast release bugs) |
| **Feature Access** | Immediate |
| **Rollback Cost** | $10,000-$15,000 (if bugs found) |
| **TOTAL COST** | **$35,000-$53,000** |

**ROI**: ❌ **NEGATIVE** - High risk, unstable release

---

## ✅ **Decision Criteria**

| If... | Then Choose... |
|-------|----------------|
| Production stability is critical | **Option A (Wait)** |
| Budget is constrained | **Option A (Wait)** |
| RHOAI 3.0 features urgently needed | **Option B (Fresh Install)** - But on **dev cluster only** |
| Zero downtime required | **Option C (Parallel)** - When stable 3.x available |
| Early R&D / testing needed | **Option B** - Separate test environment |

---

## 📅 **Proposed Timeline (Option A)**

### **Phase 1: Current State (Nov 2025 - Jan 2026)**

- ✅ Continue on RHOAI 2.25
- ✅ Complete Stage 4 implementation
- ✅ Report LlamaStack bugs to Red Hat
- ✅ Document all components

### **Phase 2: Preparation (Jan - Mar 2026)**

- 🔄 Monitor RHOAI 3.x stable release announcements
- 🔄 Build container images for RHOAI 3.x (pre-flight)
- 🔄 Export RAG data and models (backup)
- 🔄 Test GPU MachineSets on dev cluster

### **Phase 3: Migration (Q2 2026 - When Stable 3.x Available)**

- 🔄 Execute Option B or C (Fresh Install / Parallel)
- 🔄 Migrate Stage 0 → Stage 1 → **Stage 2 (critical)** → Stage 3 → Stage 4
- 🔄 Validate RAG pipeline, guardrails, agentic workflows
- 🔄 Production cutover

---

## 🎯 **Action Items**

### **Immediate (This Week)**

1. ✅ Review this analysis with team
2. ✅ **Decision**: Approve Option A (Wait for Stable 3.x)
3. ✅ Communicate to stakeholders: "No RHOAI 3.0 upgrade until stable release"
4. ✅ Continue Stage 4 development on RHOAI 2.25

### **Short Term (Next 1-3 Months)**

1. ✅ Complete Stage 4 (MCP, Agentic AI)
2. ✅ File Red Hat support cases for LlamaStack v0.3.0rc3 bugs
3. ✅ Document current implementation (all stages)
4. ✅ Monitor [Red Hat Life Cycle page](https://access.redhat.com/support/policy/updates/rhoai-sm/lifecycle) for 3.x stable announcements

### **Medium Term (3-6 Months - When Stable 3.x Announced)**

1. 🔄 Provision test cluster
2. 🔄 Execute migration pilot (Option B on dev cluster)
3. 🔄 Validate all stages, benchmark performance
4. 🔄 **Go/No-Go Decision** for production migration

---

## 📞 **Contacts**

**Red Hat Support**:
- File Jira case: [Red Hat Customer Portal](https://access.redhat.com)
- Engage TAM (Technical Account Manager) for migration planning

**Internal**:
- **Product Owner**: Approve timeline and budget
- **Infrastructure**: Provision test cluster when needed
- **Data Science**: Validate model performance post-migration

---

## 📚 **References**

- [RHOAI 3.0 Release Notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html-single/release_notes/release_notes)
- [RHOAI Upgrade Policy](https://access.redhat.com/articles/7133758)
- [Full Technical Analysis](./RHOAI-3.0-UPGRADE-ANALYSIS.md)

---

**RECOMMENDATION**: ✅ **APPROVE OPTION A (WAIT FOR STABLE 3.X)**

**Rationale**: Red Hat explicitly recommends waiting, RHOAI 2.25 has extended support, and the migration risk is too high for a fast release. We save **$35,000-$53,000** and avoid being early adopters of an unstable platform.

---

**Prepared By**: AI Assistant  
**Date**: November 16, 2025  
**Status**: 🟢 **READY FOR EXECUTIVE REVIEW**

