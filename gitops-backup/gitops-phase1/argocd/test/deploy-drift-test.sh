#!/bin/bash
#
# Deploy ArgoCD Drift Detection Application
# Purpose: Test current GitOps structure and identify drift
# Phase: 1 (Baseline Analysis)
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   ArgoCD Drift Detection - Deployment Script${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Step 1: Check prerequisites
echo -e "${YELLOW}Step 1: Checking prerequisites...${NC}"

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    echo -e "${RED}❌ Error: 'oc' command not found${NC}"
    echo "Please install the OpenShift CLI"
    exit 1
fi
echo -e "${GREEN}✅ OpenShift CLI installed${NC}"

# Check if logged into OpenShift
if ! oc whoami &> /dev/null; then
    echo -e "${RED}❌ Error: Not logged into OpenShift${NC}"
    echo "Please login: oc login ..."
    exit 1
fi
echo -e "${GREEN}✅ Logged into OpenShift: $(oc whoami)${NC}"

# Check if openshift-gitops namespace exists
if ! oc get namespace openshift-gitops &> /dev/null; then
    echo -e "${RED}❌ Error: OpenShift GitOps not installed${NC}"
    echo "Please install OpenShift GitOps operator first"
    exit 1
fi
echo -e "${GREEN}✅ OpenShift GitOps installed${NC}"

# Check if private-ai-demo namespace exists
if ! oc get namespace private-ai-demo &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: private-ai-demo namespace not found${NC}"
    echo "This is okay if testing on a fresh cluster"
fi

echo ""

# Step 2: Check Git configuration
echo -e "${YELLOW}Step 2: Checking Git configuration...${NC}"

# Check if Git remote is configured
GIT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")

if [ -z "$GIT_REMOTE" ]; then
    echo -e "${YELLOW}⚠️  Warning: No Git remote configured${NC}"
    echo ""
    echo "You need to:"
    echo "  1. Create a GitHub repository"
    echo "  2. Add remote: git remote add origin https://github.com/YOUR_ORG/private-ai-demo.git"
    echo "  3. Push branch: git push -u origin gitops-refactoring"
    echo "  4. Update app-drift-detection.yaml with your repo URL"
    echo ""
    read -p "Do you want to continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo -e "${GREEN}✅ Git remote configured: $GIT_REMOTE${NC}"
    
    # Check if app-drift-detection.yaml needs update
    if grep -q "YOUR_ORG" gitops/argocd/test/app-drift-detection.yaml; then
        echo -e "${YELLOW}⚠️  Warning: app-drift-detection.yaml still has placeholder URL${NC}"
        echo "Please update repoURL in app-drift-detection.yaml with: $GIT_REMOTE"
        echo ""
        read -p "Update now? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sed -i '' "s|https://github.com/YOUR_ORG/private-ai-demo.git|$GIT_REMOTE|g" gitops/argocd/test/app-drift-detection.yaml
            echo -e "${GREEN}✅ Updated app-drift-detection.yaml${NC}"
        fi
    else
        echo -e "${GREEN}✅ app-drift-detection.yaml configured${NC}"
    fi
fi

echo ""

# Step 3: Validate manifests
echo -e "${YELLOW}Step 3: Validating Kustomize build...${NC}"

if ! kustomize build gitops/argocd/test > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: Kustomize build failed${NC}"
    echo "Please fix errors in gitops/argocd/test/"
    exit 1
fi
echo -e "${GREEN}✅ Kustomize build successful${NC}"

echo ""

# Step 4: Deploy ArgoCD Application
echo -e "${YELLOW}Step 4: Deploying ArgoCD Application...${NC}"

if oc apply -k gitops/argocd/test; then
    echo -e "${GREEN}✅ ArgoCD Application deployed${NC}"
else
    echo -e "${RED}❌ Error: Failed to deploy ArgoCD Application${NC}"
    exit 1
fi

echo ""

# Step 5: Wait for Application to be created
echo -e "${YELLOW}Step 5: Waiting for Application to be recognized...${NC}"
sleep 5

# Check if Application exists
if oc get application private-ai-demo-drift-test -n openshift-gitops &> /dev/null; then
    echo -e "${GREEN}✅ Application created: private-ai-demo-drift-test${NC}"
else
    echo -e "${YELLOW}⚠️  Application may take a moment to appear${NC}"
fi

echo ""

# Step 6: Get ArgoCD UI access information
echo -e "${YELLOW}Step 6: ArgoCD UI Access Information${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Get ArgoCD route
ARGOCD_ROUTE=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [ -n "$ARGOCD_ROUTE" ]; then
    echo -e "${GREEN}ArgoCD URL: https://$ARGOCD_ROUTE${NC}"
else
    echo -e "${YELLOW}Could not retrieve ArgoCD route${NC}"
fi

# Get admin password
echo ""
echo "Admin Username: admin"
echo -n "Admin Password: "
oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' 2>/dev/null | base64 -d && echo "" || echo -e "${YELLOW}Could not retrieve password${NC}"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

# Step 7: Next steps
echo ""
echo -e "${GREEN}✅ Deployment Complete!${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Access ArgoCD UI (URL above)"
echo "  2. Find application: private-ai-demo-drift-test"
echo "  3. Review sync status and identify drift"
echo "  4. Document findings in docs/DRIFT-ANALYSIS.md"
echo ""
echo "For detailed instructions, see:"
echo "  gitops/argocd/test/README.md"
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

