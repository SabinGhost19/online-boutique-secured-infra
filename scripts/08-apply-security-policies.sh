#!/bin/bash
# =============================================================================
# Script: 08-apply-security-policies.sh
# Descriere: Aplică NetworkPolicies și Istio Security Policies
# =============================================================================
# ATENȚIE: Acest script aplică politici restrictive!
# Rulează-l doar după ce Online Boutique este deployed și funcțional.
# =============================================================================

set -e

echo "=============================================="
echo "APLICARE SECURITY POLICIES"
echo "=============================================="

# Culori
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# =============================================================================
# PRE-CHECK: Verifică că aplicația funcționează
# =============================================================================
echo ""
echo ">>> Pre-check: Verificare că Online Boutique funcționează..."

FRONTEND_POD=$(kubectl get pods -n develop -l app=frontend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$FRONTEND_POD" ]; then
    echo -e "${RED}✗${NC} Frontend pod nu există!"
    echo "Rulează mai întâi: ./07-deploy-online-boutique.sh"
    exit 1
fi

FRONTEND_STATUS=$(kubectl get pod $FRONTEND_POD -n develop -o jsonpath='{.status.phase}')
if [ "$FRONTEND_STATUS" != "Running" ]; then
    echo -e "${RED}✗${NC} Frontend pod nu este Running (status: $FRONTEND_STATUS)"
    exit 1
fi

echo -e "${GREEN}✓${NC} Frontend pod este Running"

# =============================================================================
# PASUL 1: Aplică NetworkPolicies de bază
# =============================================================================
echo ""
echo ">>> [1/5] Aplicare NetworkPolicies de bază..."

echo "Aplicare default-deny-all..."
kubectl apply -f "${ROOT_DIR}/network-policies/base/default-deny-all.yaml"

echo "Aplicare allow-dns..."
kubectl apply -f "${ROOT_DIR}/network-policies/base/allow-dns.yaml"

echo "Aplicare allow-istio-control-plane..."
kubectl apply -f "${ROOT_DIR}/network-policies/base/allow-istio-control-plane.yaml"

echo -e "${GREEN}✓${NC} NetworkPolicies de bază aplicate"

# =============================================================================
# PASUL 2: Aplică NetworkPolicies pentru Online Boutique
# =============================================================================
echo ""
echo ">>> [2/5] Aplicare NetworkPolicies pentru Online Boutique..."

kubectl apply -f "${ROOT_DIR}/network-policies/develop/online-boutique-policies.yaml"

echo -e "${GREEN}✓${NC} NetworkPolicies Online Boutique aplicate"

# Verificare
echo ""
echo "NetworkPolicies în develop:"
kubectl get networkpolicies -n develop

# =============================================================================
# PASUL 3: Aplică Istio PeerAuthentication (mTLS)
# =============================================================================
echo ""
echo ">>> [3/5] Aplicare Istio PeerAuthentication (mTLS strict)..."

kubectl apply -f "${ROOT_DIR}/istio-policies/peer-authentication-strict.yaml"

echo -e "${GREEN}✓${NC} PeerAuthentication aplicată"

# Verificare
echo ""
echo "PeerAuthentication policies:"
kubectl get peerauthentication -A

# =============================================================================
# PASUL 4: Aplică Istio AuthorizationPolicies
# =============================================================================
echo ""
echo -e "${YELLOW}>>> [4/5] Aplicare Istio AuthorizationPolicies...${NC}"
echo -e "${YELLOW}ATENȚIE: Aceasta va restricționa traficul la nivel L7!${NC}"

read -p "Continuă? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Skipping AuthorizationPolicies..."
else
    # NU aplica deny-all global încă - poate bloca tot
    # kubectl apply -f "${ROOT_DIR}/istio-policies/authorization-deny-all.yaml"
    
    # Aplică politicile pentru Online Boutique
    kubectl apply -f "${ROOT_DIR}/istio-policies/online-boutique/develop/authorization-policies.yaml"
    
    echo -e "${GREEN}✓${NC} AuthorizationPolicies aplicate"
fi

# Verificare
echo ""
echo "AuthorizationPolicies în develop:"
kubectl get authorizationpolicies -n develop

# =============================================================================
# PASUL 5: Verificare conectivitate
# =============================================================================
echo ""
echo ">>> [5/5] Verificare conectivitate post-policies..."

echo ""
echo "Test 1: Frontend poate accesa productcatalog?"
kubectl exec -n develop deploy/frontend -c server -- \
    wget --timeout=5 -qO- http://productcatalogservice:3550/health 2>/dev/null && \
    echo -e "${GREEN}✓${NC} Frontend -> ProductCatalog: OK" || \
    echo -e "${YELLOW}!${NC} Frontend -> ProductCatalog: Verifică politicile"

echo ""
echo "Test 2: Frontend poate accesa cartservice?"
kubectl exec -n develop deploy/frontend -c server -- \
    wget --timeout=5 -qO- http://cartservice:7070/health 2>/dev/null && \
    echo -e "${GREEN}✓${NC} Frontend -> CartService: OK" || \
    echo -e "${YELLOW}!${NC} Frontend -> CartService: Verifică politicile"

echo ""
echo "Test 3: Verificare mTLS status..."
if command -v istioctl &> /dev/null; then
    istioctl x check-mTLS frontend.develop 2>/dev/null || true
else
    echo "istioctl nu este instalat - skip verificare mTLS"
fi

# =============================================================================
# SUMAR
# =============================================================================
echo ""
echo "=============================================="
echo "SECURITY POLICIES APLICATE"
echo "=============================================="
echo ""
echo "NetworkPolicies:"
kubectl get networkpolicies -n develop --no-headers | wc -l
echo " politici în develop"
echo ""
echo "Istio Policies:"
echo "- PeerAuthentication: $(kubectl get peerauthentication -n develop --no-headers 2>/dev/null | wc -l) în develop"
echo "- AuthorizationPolicy: $(kubectl get authorizationpolicies -n develop --no-headers 2>/dev/null | wc -l) în develop"
echo ""

echo "=============================================="
echo "VERIFICARE ÎN KIALI"
echo "=============================================="
echo ""
echo "Pentru a vizualiza security status:"
echo "  kubectl port-forward svc/kiali -n istio-system 20001:20001"
echo "  Accesează: http://localhost:20001"
echo ""
echo "În Kiali, verifică:"
echo "1. Graph → Display → Security (iconițe lacăt pentru mTLS)"
echo "2. Workloads → selectează un workload → verifică 'Security'"
echo "3. Istio Config → verifică că toate config-urile sunt valide (✓)"
echo ""

echo "=============================================="
echo "TROUBLESHOOTING"
echo "=============================================="
echo ""
echo "Dacă ceva nu funcționează:"
echo ""
echo "1. Verifică logs Istio proxy:"
echo "   kubectl logs deploy/frontend -n develop -c istio-proxy | tail -50"
echo ""
echo "2. Verifică că sidecar-ul există:"
echo "   kubectl get pods -n develop -o jsonpath='{.items[*].spec.containers[*].name}' | tr ' ' '\n' | sort | uniq -c"
echo ""
echo "3. Analizează mesh-ul pentru erori:"
echo "   istioctl analyze -n develop"
echo ""
echo "4. Verifică deny-uri în AuthorizationPolicy:"
echo "   kubectl logs deploy/istiod -n istio-system | grep -i 'denied'"
echo ""
