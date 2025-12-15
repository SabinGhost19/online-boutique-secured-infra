#!/bin/bash
# =============================================================================
# Script: 07-deploy-online-boutique.sh
# Descriere: Deployează Online Boutique folosind Kustomize
# =============================================================================

set -e

echo "=============================================="
echo "DEPLOY ONLINE BOUTIQUE"
echo "=============================================="

# Culori
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Directoare
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# =============================================================================
# PASUL 1: Verificare fișiere locale (GitOps Mode)
# =============================================================================
echo ""
echo ">>> [1/6] Verificare manifeste locale..."

ONLINE_BOUTIQUE_DIR="${ROOT_DIR}/online-boutique"

if [ ! -f "${ONLINE_BOUTIQUE_DIR}/base/kubernetes-manifests.yaml" ]; then
    echo -e "${RED}Eroare: Manifestele de bază lipsesc!${NC}"
    echo "Rulează 'curl -L https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml -o online-boutique/base/kubernetes-manifests.yaml'"
    exit 1
fi

echo -e "${GREEN}✓${NC} Manifeste locale găsite"

# =============================================================================
# PASUL 2: Verificare Kustomization overlays
# =============================================================================
echo ""
echo ">>> [2/6] Verificare Kustomization overlays..."

# Develop overlay
if [ ! -f "${ONLINE_BOUTIQUE_DIR}/overlays/develop/kustomization.yaml" ]; then
    echo "Creare develop overlay..."
    mkdir -p "${ONLINE_BOUTIQUE_DIR}/overlays/develop"
    cat > "${ONLINE_BOUTIQUE_DIR}/overlays/develop/kustomization.yaml" << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: develop

resources:
  - ../../base
  - ingress.yaml

commonLabels:
  environment: develop

# Replici reduse pentru develop
replicas:
  - name: frontend
    count: 1
  - name: cartservice
    count: 1
  - name: productcatalogservice
    count: 1
  - name: currencyservice
    count: 1
  - name: paymentservice
    count: 1
  - name: shippingservice
    count: 1
  - name: emailservice
    count: 1
  - name: checkoutservice
    count: 1
  - name: recommendationservice
    count: 1
  - name: adservice
    count: 1
  - name: redis-cart
    count: 1
EOF
    echo -e "${GREEN}✓${NC} Develop overlay creat/verificat"
fi

# Prod overlay
if [ ! -f "${ONLINE_BOUTIQUE_DIR}/overlays/prod/kustomization.yaml" ]; then
    echo "Creare prod overlay..."
    mkdir -p "${ONLINE_BOUTIQUE_DIR}/overlays/prod"
    cat > "${ONLINE_BOUTIQUE_DIR}/overlays/prod/kustomization.yaml" << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: prod

resources:
  - ../../base
  - hpa.yaml
  - pdb.yaml

commonLabels:
  environment: prod

# Replici pentru production
replicas:
  - name: frontend
    count: 3
  - name: cartservice
    count: 2
  - name: productcatalogservice
    count: 2
  - name: currencyservice
    count: 2
  - name: paymentservice
    count: 2
  - name: shippingservice
    count: 2
  - name: emailservice
    count: 2
  - name: checkoutservice
    count: 2
  - name: recommendationservice
    count: 2
  - name: adservice
    count: 2
  - name: redis-cart
    count: 1
EOF
    echo -e "${GREEN}✓${NC} Prod overlay creat/verificat"
fi

# HPA pentru prod
if [ ! -f "${ONLINE_BOUTIQUE_DIR}/overlays/prod/hpa.yaml" ]; then
    cat > "${ONLINE_BOUTIQUE_DIR}/overlays/prod/hpa.yaml" << 'EOF'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: frontend-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: frontend
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: checkoutservice-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: checkoutservice
  minReplicas: 2
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
EOF
fi

# PDB pentru prod
if [ ! -f "${ONLINE_BOUTIQUE_DIR}/overlays/prod/pdb.yaml" ]; then
    cat > "${ONLINE_BOUTIQUE_DIR}/overlays/prod/pdb.yaml" << 'EOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: frontend-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: frontend
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: checkoutservice-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: checkoutservice
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: cartservice-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: cartservice
EOF
fi

# =============================================================================
# PASUL 3: Verifică că namespace-urile există și au Istio injection
# =============================================================================
echo ""
echo ">>> [3/6] Verificare namespace-uri..."

for NS in develop prod; do
    if ! kubectl get namespace $NS &> /dev/null; then
        echo "Creare namespace $NS..."
        kubectl create namespace $NS
    fi
    
    # Verifică Istio injection label
    ISTIO_LABEL=$(kubectl get namespace $NS -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null)
    if [ "$ISTIO_LABEL" != "enabled" ]; then
        echo "Activare Istio injection pentru $NS..."
        kubectl label namespace $NS istio-injection=enabled --overwrite
    fi
done

echo -e "${GREEN}✓${NC} Namespace-uri configurate"

# =============================================================================
# PASUL 4: Deploy în develop
# =============================================================================
echo ""
echo ">>> [4/6] Deploy în namespace develop..."

# Preview (dry-run)
echo "Preview modificări (kustomize build)..."
kubectl kustomize "${ONLINE_BOUTIQUE_DIR}/overlays/develop" | head -50
echo "..."

# Aplică
echo ""
echo "Aplicare..."
kubectl apply -k "${ONLINE_BOUTIQUE_DIR}/overlays/develop"

echo -e "${GREEN}✓${NC} Deploy în develop complet"

# =============================================================================
# PASUL 5: Așteaptă ca podurile să fie ready
# =============================================================================
echo ""
echo ">>> [5/6] Așteptare poduri să fie ready..."

echo "Așteptare pentru deployments în develop..."
kubectl wait --for=condition=available deployment --all \
    -n develop --timeout=300s || {
    echo -e "${YELLOW}!${NC} Unele deployments nu sunt încă ready"
    echo "Verifică status cu: kubectl get pods -n develop"
}

# =============================================================================
# PASUL 6: Verificare
# =============================================================================
echo ""
echo ">>> [6/6] Verificare deployment..."

echo ""
echo "Poduri în develop:"
kubectl get pods -n develop

echo ""
echo "Servicii în develop:"
kubectl get svc -n develop

echo ""
echo "Verificare Istio sidecars (2/2 = sidecar injectat):"
kubectl get pods -n develop -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}'

# =============================================================================
# INSTRUCȚIUNI ACCES
# =============================================================================
echo ""
echo "=============================================="
echo "ACCESARE ONLINE BOUTIQUE"
echo "=============================================="
echo ""
echo "Opțiunea 1: Port-forward direct către frontend:"
echo "  kubectl port-forward svc/frontend -n develop 8080:80"
echo "  Accesează: http://localhost:8080"
echo ""
echo "Opțiunea 2: Prin NGINX Ingress (configurează Ingress resource)"
echo ""
echo "Opțiunea 3: Prin Istio Gateway + VirtualService"
echo ""

echo "=============================================="
echo -e "${GREEN}ONLINE BOUTIQUE DEPLOYED${NC}"
echo "=============================================="
echo ""
echo "Următorii pași:"
echo "1. Aplică NetworkPolicies: kubectl apply -k ../network-policies/develop/"
echo "2. Aplică Istio Policies: kubectl apply -f ../istio-policies/"
echo "3. Verifică în Kiali: kubectl port-forward svc/kiali -n istio-system 20001:20001"
