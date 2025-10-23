# Service Mesh Architecture - ACME LithoOps Agent

## Overview

This document explains the Service Mesh architecture for the ACME LithoOps Agent and why the chosen pattern aligns with Red Hat OpenShift Service Mesh best practices.

## Architecture Components

### Service Mesh Version
- **Red Hat OpenShift Service Mesh 2.6.10** (based on Istio)
- Using Maistra architecture with mTLS enabled by default

### Application Components

1. **Frontend: ACME LithoOps Agent**
   - Namespace: `acme-calibration-ops`
   - Istio Sidecar: **Not injected**
   - External Access: Public OpenShift Route
   - Purpose: External-facing web UI and API

2. **Backend: vLLM (Mistral 24B)**
   - Namespace: `private-ai-demo`
   - Istio Sidecar: **Injected** (part of Service Mesh)
   - Access: Public HTTPS route
   - Purpose: LLM inference service

3. **Backend: MCP Servers (Slack, Database)**
   - Namespace: `private-ai-demo`
   - Istio Sidecar: Configuration TBD
   - Access: Internal services

## Communication Pattern

```
┌─────────────────────────────────────────────────────────────┐
│  Internet / External Users                                  │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTPS
                     ▼
         ┌───────────────────────┐
         │  OpenShift Router     │
         └───────────┬───────────┘
                     │
                     ▼
    ┌────────────────────────────────────────┐
    │  acme-calibration-ops namespace        │
    │                                        │
    │  ┌──────────────────────────────────┐ │
    │  │  ACME LithoOps Agent             │ │
    │  │  (NO Istio sidecar)              │ │
    │  │                                  │ │
    │  │  - REST API                      │ │
    │  │  - Web UI                        │ │
    │  │  - LangChain4j Integration       │ │
    │  └──────────┬───────────────────────┘ │
    └─────────────┼──────────────────────────┘
                  │ HTTPS via Public Route
                  ▼
    ┌────────────────────────────────────────┐
    │  private-ai-demo namespace             │
    │  (Service Mesh enabled)                │
    │                                        │
    │  ┌──────────────────────────────────┐ │
    │  │  vLLM (Mistral 24B)              │ │
    │  │  [Istio sidecar injected]        │ │
    │  │                                  │ │
    │  │  - mTLS enabled                  │ │
    │  │  - KServe/Knative                │ │
    │  │  - Public route available        │ │
    │  └──────────────────────────────────┘ │
    │                                        │
    │  ┌──────────────────────────────────┐ │
    │  │  MCP Servers                     │ │
    │  │  - Slack MCP                     │ │
    │  │  - Database MCP                  │ │
    │  └──────────────────────────────────┘ │
    └────────────────────────────────────────┘
```

## Design Decisions

### Why NO Istio Sidecar on ACME Agent?

According to [Red Hat Service Mesh documentation](https://developers.redhat.com/articles/2025/09/25/unlocking-power-openshift-service-mesh-3), this is the **recommended pattern** for external-facing applications:

1. **External Access Simplicity**
   - External-facing applications that need to accept traffic from outside the cluster should not have Istio sidecars
   - Sidecars complicate ingress routing and certificate management
   - OpenShift Routes work seamlessly with pods without sidecars

2. **Hybrid Architecture Support**
   - Not all services need to be in the mesh
   - The mesh is for service-to-service communication within the cluster
   - External-facing services can use public routes to access mesh services

3. **Operational Simplicity**
   - Reduces complexity of certificate management
   - Eliminates issues with Istio route-pod communication
   - Easier to troubleshoot and monitor

### Why Use Public Route for vLLM Access?

1. **Knative + Istio Complexity**
   - Knative services with Istio sidecars have complex networking requirements
   - Internal ClusterIP access requires both pods to be in the mesh
   - PeerAuthentication PERMISSIVE mode alone is insufficient due to Knative networking

2. **Valid Architectural Pattern**
   - Red Hat supports hybrid architectures where some services are in the mesh and some are not
   - Public routes provide a stable, well-understood access pattern
   - Security is maintained through OpenShift's route-level TLS termination

3. **Production Ready**
   - Public routes are load-balanced and highly available
   - Easier to monitor and debug
   - Consistent with other external→internal communication patterns

## Security Considerations

### TLS/mTLS
- **External→Frontend:** TLS via OpenShift Router
- **Frontend→vLLM:** HTTPS via public route
- **Mesh Services:** mTLS (automatic via Istio)

### Network Policies
We have NetworkPolicies in place to control traffic:
- Allow ingress from `acme-calibration-ops` to `private-ai-demo`
- Allow ingress to vLLM predictor pods
- Default deny policies for other traffic

### PeerAuthentication
A `PeerAuthentication` policy is configured for vLLM with PERMISSIVE mode:
```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: mistral-permissive
  namespace: private-ai-demo
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: mistral-24b-quantized
  mtls:
    mode: PERMISSIVE
```

This allows the service to accept both mTLS (from mesh services) and plain text (from non-mesh services).

## Alternative Approaches Considered

### 1. Both Pods in Mesh
**Pros:**
- Full mTLS encryption
- Service mesh observability

**Cons:**
- Complex external access via Istio Gateway
- Certificate management complexity
- Route→Istio Gateway→Pod routing complexity
- Not recommended for external-facing applications

**Decision:** Rejected - Adds unnecessary complexity for external-facing frontend

### 2. Internal ClusterIP Access
**Pros:**
- Direct pod-to-pod communication
- Lower latency (no extra hop)

**Cons:**
- Requires both pods in mesh OR complex PeerAuthentication configs
- Knative networking adds additional complexity
- Istio CNI requirements
- Failed in testing due to Knative + Istio networking issues

**Decision:** Rejected - Too complex and unreliable

### 3. Public Route Access (CHOSEN)
**Pros:**
- Simple and reliable
- Well-understood pattern
- Works with hybrid mesh/non-mesh architectures
- Recommended by Red Hat for external-facing apps

**Cons:**
- One extra network hop (negligible latency)
- Uses public route infrastructure

**Decision:** ACCEPTED - Best balance of simplicity and reliability

## Configuration Files

### Application Configuration
`src/main/resources/application.properties`:
```properties
quarkus.langchain4j.openai.base-url=https://mistral-24b-quantized-private-ai-demo.apps.cluster-n8cnx.n8cnx.sandbox2830.opentlc.com/v1
```

### Deployment Configuration
`deploy/deployment.yaml`:
```yaml
annotations:
  sidecar.istio.io/inject: "false"  # No sidecar for external-facing frontend
```

### NetworkPolicies
- `deploy/networkpolicy-allow-from-acme.yaml`
- `deploy/networkpolicy-allow-acme-calibration-ops-to-predictor.yaml`

### PeerAuthentication
- `deploy/peerauthentication.yaml`

## References

- [Red Hat OpenShift Service Mesh 3.0 Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.0)
- [Unlocking the Power of OpenShift Service Mesh 3](https://developers.redhat.com/articles/2025/09/25/unlocking-power-openshift-service-mesh-3)
- [Solution Pattern: OpenShift Service Mesh - Empowering Teams and Exploring OSSM 3 Tech](https://developers.redhat.com/blog/2025/01/23/solution-pattern-openshift-service-mesh-empowering-teams-and-exploring-ossm-3-tech)

## Troubleshooting

### Connection Reset Errors
If you see `java.net.SocketException: Connection reset`, check:
1. Is the application configured to use the public HTTPS route?
2. Is the PeerAuthentication policy applied?
3. Are NetworkPolicies allowing the traffic?
4. Is the vLLM service healthy and responding?

### Verify Configuration
```bash
# Check application configuration
oc get deployment acme-agent -n acme-calibration-ops -o yaml | grep -A 5 "annotations:"

# Check PeerAuthentication
oc get peerauthentication -n private-ai-demo

# Test vLLM access from outside the mesh
curl -k https://mistral-24b-quantized-private-ai-demo.apps.cluster-n8cnx.n8cnx.sandbox2830.opentlc.com/v1/models
```

## Conclusion

This architecture follows Red Hat best practices for hybrid Service Mesh deployments where external-facing applications need to communicate with mesh-enabled backend services. The pattern is simple, reliable, and production-ready.

