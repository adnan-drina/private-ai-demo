# GuideLLM Integration Documentation

This directory contains the complete documentation for the GuideLLM integration in Stage 3 (Model Monitoring).

## 📚 Documentation Index

### Planning & Design
1. **[01-IMPLEMENTATION-PLAN.md](01-IMPLEMENTATION-PLAN.md)** - Initial comprehensive 6-phase implementation plan
2. **[02-REVISED-PLAN.md](02-REVISED-PLAN.md)** - Revised plan using official container images (minimal custom code)
3. **[03-SUMMARY.md](03-SUMMARY.md)** - Executive summary for stakeholders
4. **[04-DIRECTORY-STRUCTURE.md](04-DIRECTORY-STRUCTURE.md)** - Proposed file organization

### Implementation & Status
5. **[05-DEPLOYMENT-STATUS.md](05-DEPLOYMENT-STATUS.md)** - Initial deployment status and troubleshooting
6. **[06-FINAL-STATUS.md](06-FINAL-STATUS.md)** - Final status with remaining issues and next steps
7. **[10-IMPLEMENTATION-COMPLETE.md](10-IMPLEMENTATION-COMPLETE.md)** - Implementation completion summary
8. **[11-FINAL-COMPLETE.md](11-FINAL-COMPLETE.md)** - Final complete solution handover

### Usage & Operations
9. **[07-CONSOLE-USAGE.md](07-CONSOLE-USAGE.md)** - OpenShift Console usage guide for managing jobs
10. **[09-COMPLETE-SUMMARY.md](09-COMPLETE-SUMMARY.md)** - Complete summary with API fixes and GUI access

### Issues & Resolutions
11. **[08-ROUTING-FIXED.md](08-ROUTING-FIXED.md)** - Routing fix details
12. **[12-SUCCESS-SUMMARY.md](12-SUCCESS-SUMMARY.md)** - Successful benchmark execution and UI implementation

## 🎯 Quick Start

For a quick overview, read:
1. [02-REVISED-PLAN.md](02-REVISED-PLAN.md) - Understand the architecture
2. [07-CONSOLE-USAGE.md](07-CONSOLE-USAGE.md) - Learn how to use it
3. [12-SUCCESS-SUMMARY.md](12-SUCCESS-SUMMARY.md) - See what's working

## ⚠️ Known Issues

**HTML Reports UI Issue**: The GuideLLM HTML reports generated with `GUIDELLM__ENV=prod` display empty data due to a Next.js SSR framework incompatibility. The benchmark data is captured correctly (verified in raw HTML), but the UI cannot read it. This is an upstream GuideLLM bug, not a configuration issue.

**Workaround**: Extract metrics from job logs or raw HTML data.

## 📊 What's Working

- ✅ GuideLLM benchmark jobs execute successfully
- ✅ Performance metrics captured (TTFT, ITL, throughput)
- ✅ Reports uploaded to MinIO S3
- ✅ Scheduled daily/weekly benchmarks via CronJobs
- ✅ Manual job launching via OpenShift Console

## 🔗 Related Documentation

- [GUIDELLM-INTEGRATION.md](../../GUIDELLM-INTEGRATION.md) - Main integration guide
- [Troubleshooting](../troubleshooting/) - Issue resolution documentation
