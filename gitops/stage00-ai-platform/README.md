# Stage 00: AI Platform

Stage 00 delivers the foundational OpenShift AI infrastructure (operators,
GPU nodes, DataScienceCluster, MinIO). All Kubernetes resources live under
`gitops/stage00-ai-platform` and are reconciled by ArgoCD applications.

## Deployment Workflow

1. Populate the repository `.env` with MinIO credentials:
   ```bash
   MINIO_ACCESS_KEY=...
   MINIO_SECRET_KEY=...
   ```
2. Run the helper script to create secrets and request ArgoCD syncs:
   ```bash
   ./stages/stage0-ai-platform/deploy.sh
   ```
3. Monitor reconciliation status:
   ```bash
   oc get applications.argoproj.io -n openshift-gitops stage00-operators stage00-gpu-infrastructure stage00-datasciencecluster stage00-minio
   ```

The script **never** applies manifests directly; it only manages secrets and
delegates all resource changes to ArgoCD.

## Structure

- `operators/` – Operator subscriptions and namespaces
- `gpu-infrastructure/` – MachineSets and NVIDIA ClusterPolicy
- `datasciencecluster/` – DataScienceCluster CR and service mesh dependencies
- `minio/` – MinIO deployment (credentials supplied via `.env`)

> Stage 00 must be healthy before progressing to higher stages.

