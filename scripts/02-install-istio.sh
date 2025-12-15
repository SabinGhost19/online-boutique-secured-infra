#!/bin/bash
# =============================================================================
# Script: 02-install-istio.sh
# Descriere: Instalează Istio Service Mesh folosind Helm
# Versiune Istio: 1.24.x (compatibilă cu K8s 1.29)
# =============================================================================

set -e

echo "=============================================="
echo "INSTALARE ISTIO SERVICE MESH"
echo "=============================================="

# Variabile
ISTIO_VERSION="1.24.0"
NAMESPACE="istio-system"

# Culori
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo ">>> Adăugare repository Helm Istio..."
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

echo ""
echo ">>> Verificare versiuni disponibile..."
helm search repo istio/base --versions | head -10

echo ""
echo -e "${YELLOW}Se va instala Istio versiunea: ${ISTIO_VERSION}${NC}"
echo ""

# =============================================================================
# PASUL 1: Instalare istio-base (CRDs)
# =============================================================================
echo ">>> [1/3] Instalare istio-base (CRDs)..."

helm upgrade --install istio-base istio/base \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --version ${ISTIO_VERSION} \
    --values ../istio/istio-base-values.yaml \
    --wait

echo -e "${GREEN}✓${NC} istio-base instalat"

# Verificare CRDs
echo ""
echo ">>> Verificare CRDs Istio..."
kubectl get crds | grep istio | head -10

# =============================================================================
# PASUL 2: Instalare istiod (Control Plane)
# =============================================================================
echo ""
echo ">>> [2/3] Instalare istiod (Control Plane)..."

helm upgrade --install istiod istio/istiod \
    --namespace ${NAMESPACE} \
    --version ${ISTIO_VERSION} \
    --values ../istio/istiod-values.yaml \
    --wait --timeout 5m

echo -e "${GREEN}✓${NC} istiod instalat"

# Așteaptă ca istiod să fie ready
echo ""
echo ">>> Așteptare istiod să fie ready..."
kubectl wait --for=condition=available deployment/istiod \
    -n ${NAMESPACE} --timeout=300s

# =============================================================================
# PASUL 3: Instalare Istio Ingress Gateway (opțional)
# =============================================================================
echo ""
echo ">>> [3/3] Instalare Istio Ingress Gateway..."

# Creăm namespace-ul pentru gateway dacă nu există
kubectl create namespace istio-ingress --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace istio-ingress istio-injection=enabled --overwrite

helm upgrade --install istio-ingressgateway istio/gateway \
    --namespace istio-ingress \
    --version ${ISTIO_VERSION} \
    --values ../istio/gateway-values.yaml \
    --wait

echo -e "${GREEN}✓${NC} Istio Gateway instalat"

# =============================================================================
# VERIFICĂRI FINALE
# =============================================================================
echo ""
echo "=============================================="
echo "VERIFICARE INSTALARE ISTIO"
echo "=============================================="

echo ""
echo ">>> Poduri în istio-system:"
kubectl get pods -n ${NAMESPACE}

echo ""
echo ">>> Poduri în istio-ingress:"
kubectl get pods -n istio-ingress

echo ""
echo ">>> Servicii Istio:"
kubectl get svc -n ${NAMESPACE}

echo ""
echo ">>> Verificare versiune Istio instalată:"
kubectl get deployment istiod -n ${NAMESPACE} \
    -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""

echo ""
echo ">>> Verificare IstioOperator (dacă există):"
kubectl get istiooperator -A 2>/dev/null || echo "Nu se folosește IstioOperator (instalare Helm)"

echo ""
echo ">>> Verificare că namespace-urile au label istio-injection:"
kubectl get namespace -l istio-injection=enabled

# =============================================================================
# INSTALARE ISTIOCTL (opțional dar recomandat)
# =============================================================================
echo ""
echo "=============================================="
echo "INSTALARE ISTIOCTL CLI"
echo "=============================================="

if command -v istioctl &> /dev/null; then
    echo -e "${GREEN}✓${NC} istioctl este deja instalat"
    istioctl version
else
    echo ">>> Descărcare și instalare istioctl..."
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VERSION} sh -
    
    # Adaugă la PATH pentru sesiunea curentă
    export PATH=$PWD/istio-${ISTIO_VERSION}/bin:$PATH
    
    echo ""
    echo "Pentru a face istioctl permanent disponibil, adaugă în ~/.bashrc sau ~/.zshrc:"
    echo "export PATH=\$PATH:$PWD/istio-${ISTIO_VERSION}/bin"
fi

echo ""
echo "=============================================="
echo -e "${GREEN}ISTIO INSTALAT CU SUCCES${NC}"
echo "=============================================="
echo ""
echo "Următorul pas: ./scripts/03-install-observability.sh"
