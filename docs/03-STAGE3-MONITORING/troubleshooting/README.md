# Stage 3 Troubleshooting Documentation

This directory contains root cause analyses and issue resolution documentation for Stage 3 (Model Monitoring).

## 📚 Documentation Index

### Grafana Dashboard Issues
- **[DASHBOARD-NO-DATA-ROOT-CAUSE-ANALYSIS.md](DASHBOARD-NO-DATA-ROOT-CAUSE-ANALYSIS.md)**
  - Root cause: Missing Prometheus receiver in OTEL Collector
  - Fixed by adding Target Allocator and proper PodMonitors

### GuideLLM Issues
- **[ISSUES-RESOLVED-SUMMARY.md](ISSUES-RESOLVED-SUMMARY.md)**
  - Job completion issues (s3-uploader sidecar)
  - Grafana "no data" issues (ServiceMonitor configuration)
  - Comprehensive troubleshooting log

## 🔍 Common Issues

### Grafana Shows "No Data"
1. Check ServiceMonitor exists for OTEL Collector
2. Verify Target Allocator is discovering targets
3. Confirm Prometheus/Thanos is scraping OTEL Collector

### GuideLLM Jobs Stuck "In Progress"
1. Check pod logs for both `guidellm` and `s3-uploader` containers
2. Verify MinIO credentials secret exists
3. Ensure sufficient cluster resources for job scheduling

## 🔗 Related Documentation

- [GuideLLM Documentation](../guidellm/) - Implementation guides
- [GUIDELLM-INTEGRATION.md](../../GUIDELLM-INTEGRATION.md) - Main integration guide
