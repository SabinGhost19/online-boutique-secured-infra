#!/bin/bash
# =============================================================================
# Script: 09-validate-security.sh
# Descriere: Validează și testează configurația de securitate
# =============================================================================

set -e

echo "=============================================="
echo "VALIDARE SECURITATE"
echo "=============================================="

# Culori
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# Funcții helper
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((PASS_COUNT++))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((FAIL_COUNT++))
}

warn() {
    echo -e "${YELLOW}! WARN${NC}: $1"
    ((WARN_COUNT++))
}

# =============================================================================
# SECȚIUNEA 1: Validare Istio
# =============================================================================
echo ""
echo "=== VALIDARE ISTIO ==="
echo ""

# Test 1.1: Istio control plane
echo "1.1 Verificare istiod..."
ISTIOD_READY=$(kubectl get deployment istiod -n istio-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
if [ "$ISTIOD_READY" -ge 1 ] 2>/dev/null; then
    pass "istiod are $ISTIOD_READY replici ready"
else
    fail "istiod nu este ready"
fi

# Test 1.2: Istio CRDs
echo "1.2 Verificare CRDs Istio..."
CRD_COUNT=$(kubectl get crds | grep -c 'istio.io' || true)
if [ "$CRD_COUNT" -ge 20 ]; then
    pass "Istio CRDs instalate ($CRD_COUNT)"
else
    fail "Istio CRDs lipsesc (doar $CRD_COUNT găsite)"
fi

# Test 1.3: mTLS PeerAuthentication
echo "1.3 Verificare mTLS STRICT..."
MTLS_MODE=$(kubectl get peerauthentication -n istio-system default -o jsonpath='{.spec.mtls.mode}' 2>/dev/null)
if [ "$MTLS_MODE" == "STRICT" ]; then
    pass "mTLS STRICT activat mesh-wide"
else
    warn "mTLS nu este STRICT (mode: $MTLS_MODE)"
fi

# Test 1.4: Sidecar injection în namespace-uri
echo "1.4 Verificare Istio injection labels..."
for NS in develop prod; do
    LABEL=$(kubectl get namespace $NS -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null)
    if [ "$LABEL" == "enabled" ]; then
        pass "Namespace $NS are istio-injection=enabled"
    else
        fail "Namespace $NS nu are istio-injection label"
    fi
done

# Test 1.5: Sidecars în poduri
echo "1.5 Verificare sidecars în poduri develop..."
PODS_TOTAL=$(kubectl get pods -n develop --no-headers 2>/dev/null | wc -l)
PODS_WITH_SIDECAR=$(kubectl get pods -n develop -o jsonpath='{.items[*].spec.containers[*].name}' 2>/dev/null | tr ' ' '\n' | grep -c 'istio-proxy' || true)
if [ "$PODS_WITH_SIDECAR" -ge "$PODS_TOTAL" ] && [ "$PODS_TOTAL" -gt 0 ]; then
    pass "Toate podurile au sidecar Istio ($PODS_WITH_SIDECAR/$PODS_TOTAL)"
else
    warn "Nu toate podurile au sidecar ($PODS_WITH_SIDECAR/$PODS_TOTAL)"
fi

# =============================================================================
# SECȚIUNEA 2: Validare NetworkPolicies
# =============================================================================
echo ""
echo "=== VALIDARE NETWORK POLICIES ==="
echo ""

# Test 2.1: Default deny
echo "2.1 Verificare default-deny-all..."
for NS in develop prod; do
    if kubectl get networkpolicy default-deny-all -n $NS &>/dev/null; then
        pass "default-deny-all există în $NS"
    else
        fail "default-deny-all lipsește în $NS"
    fi
done

# Test 2.2: Allow DNS
echo "2.2 Verificare allow-dns..."
if kubectl get networkpolicy allow-dns-egress -n develop &>/dev/null; then
    pass "allow-dns-egress există"
else
    fail "allow-dns-egress lipsește"
fi

# Test 2.3: Număr de NetworkPolicies
echo "2.3 Verificare număr NetworkPolicies..."
NP_COUNT=$(kubectl get networkpolicies -n develop --no-headers 2>/dev/null | wc -l)
if [ "$NP_COUNT" -ge 10 ]; then
    pass "$NP_COUNT NetworkPolicies în develop (expected ~15)"
else
    warn "Doar $NP_COUNT NetworkPolicies în develop"
fi

# =============================================================================
# SECȚIUNEA 3: Validare Kyverno
# =============================================================================
echo ""
echo "=== VALIDARE KYVERNO ==="
echo ""

# Test 3.1: Kyverno controller
echo "3.1 Verificare Kyverno controller..."
KYVERNO_READY=$(kubectl get deployment -n kyverno -l app.kubernetes.io/component=admission-controller -o jsonpath='{.items[0].status.readyReplicas}' 2>/dev/null)
if [ "$KYVERNO_READY" -ge 1 ] 2>/dev/null; then
    pass "Kyverno admission controller ready ($KYVERNO_READY replici)"
else
    fail "Kyverno admission controller nu este ready"
fi

# Test 3.2: ClusterPolicies
echo "3.2 Verificare ClusterPolicies..."
CP_COUNT=$(kubectl get clusterpolicies --no-headers 2>/dev/null | wc -l)
if [ "$CP_COUNT" -ge 3 ]; then
    pass "$CP_COUNT ClusterPolicies definite"
else
    warn "Doar $CP_COUNT ClusterPolicies definite"
fi

# Test 3.3: Policy violations
echo "3.3 Verificare policy violations..."
VIOLATIONS=$(kubectl get policyreport -A -o jsonpath='{.items[*].summary.fail}' 2>/dev/null | tr ' ' '+' | bc 2>/dev/null || echo "0")
if [ "$VIOLATIONS" == "0" ] || [ -z "$VIOLATIONS" ]; then
    pass "Nu sunt policy violations"
else
    warn "$VIOLATIONS policy violations detectate"
fi

# =============================================================================
# SECȚIUNEA 4: Validare ArgoCD
# =============================================================================
echo ""
echo "=== VALIDARE ARGOCD ==="
echo ""

# Test 4.1: ArgoCD server
echo "4.1 Verificare ArgoCD server..."
ARGOCD_READY=$(kubectl get deployment argocd-server -n argocd -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
if [ "$ARGOCD_READY" -ge 1 ] 2>/dev/null; then
    pass "ArgoCD server ready ($ARGOCD_READY replici)"
else
    fail "ArgoCD server nu este ready"
fi

# Test 4.2: AppProjects
echo "4.2 Verificare AppProjects..."
PROJECTS=$(kubectl get appprojects -n argocd --no-headers 2>/dev/null | wc -l)
if [ "$PROJECTS" -ge 3 ]; then
    pass "$PROJECTS AppProjects definite"
else
    warn "Doar $PROJECTS AppProjects"
fi

# =============================================================================
# SECȚIUNEA 5: Validare Sealed Secrets
# =============================================================================
echo ""
echo "=== VALIDARE SEALED SECRETS ==="
echo ""

# Test 5.1: Controller
echo "5.1 Verificare Sealed Secrets controller..."
if kubectl get deployment sealed-secrets-controller -n kube-system &>/dev/null; then
    SS_READY=$(kubectl get deployment sealed-secrets-controller -n kube-system -o jsonpath='{.status.readyReplicas}')
    if [ "$SS_READY" -ge 1 ]; then
        pass "Sealed Secrets controller ready"
    else
        fail "Sealed Secrets controller nu este ready"
    fi
else
    warn "Sealed Secrets controller nu este instalat"
fi

# =============================================================================
# SECȚIUNEA 6: Teste de conectivitate
# =============================================================================
echo ""
echo "=== TESTE CONECTIVITATE ==="
echo ""

# Test 6.1: DNS funcționează
echo "6.1 Test DNS resolution..."
if kubectl exec -n develop deploy/frontend -c server -- nslookup productcatalogservice &>/dev/null; then
    pass "DNS resolution funcționează"
else
    fail "DNS resolution nu funcționează"
fi

# Test 6.2: Frontend -> ProductCatalog
echo "6.2 Test Frontend -> ProductCatalogService..."
if kubectl exec -n develop deploy/frontend -c server -- wget --timeout=5 -qO- http://productcatalogservice:3550/ 2>/dev/null | grep -q ""; then
    pass "Frontend poate accesa ProductCatalogService"
else
    warn "Frontend nu poate accesa ProductCatalogService (verifică politicile)"
fi

# Test 6.3: Test blocare - Frontend NU ar trebui să acceseze Redis direct
echo "6.3 Test blocare Frontend -> Redis (ar trebui să fie blocat)..."
if kubectl exec -n develop deploy/frontend -c server -- timeout 3 sh -c 'echo PING | nc redis-cart 6379' 2>/dev/null | grep -q "PONG"; then
    warn "Frontend poate accesa Redis direct (ar trebui blocat)"
else
    pass "Frontend NU poate accesa Redis direct (corect!)"
fi

# =============================================================================
# SECȚIUNEA 7: Validare Security Contexts
# =============================================================================
echo ""
echo "=== VALIDARE SECURITY CONTEXTS ==="
echo ""

# Test 7.1: Poduri care rulează ca root
echo "7.1 Verificare poduri care rulează ca root..."
ROOT_PODS=$(kubectl get pods -n develop -o jsonpath='{range .items[*]}{.metadata.name}{" runAsNonRoot="}{.spec.securityContext.runAsNonRoot}{"\n"}{end}' 2>/dev/null | grep -v "true" | grep -v "istio" | wc -l)
if [ "$ROOT_PODS" -le 2 ]; then
    pass "Majoritate poduri au runAsNonRoot"
else
    warn "$ROOT_PODS poduri ar putea rula ca root"
fi

# =============================================================================
# SUMAR
# =============================================================================
echo ""
echo "=============================================="
echo "SUMAR VALIDARE"
echo "=============================================="
echo ""
echo -e "${GREEN}PASSED${NC}: $PASS_COUNT"
echo -e "${YELLOW}WARNINGS${NC}: $WARN_COUNT"
echo -e "${RED}FAILED${NC}: $FAIL_COUNT"
echo ""

TOTAL=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))
SCORE=$((PASS_COUNT * 100 / TOTAL))

echo "Scor securitate: ${SCORE}%"
echo ""

if [ "$FAIL_COUNT" -eq 0 ] && [ "$WARN_COUNT" -le 3 ]; then
    echo -e "${GREEN}✓ Configurația de securitate este bună!${NC}"
elif [ "$FAIL_COUNT" -le 2 ]; then
    echo -e "${YELLOW}! Configurația are câteva probleme minore${NC}"
else
    echo -e "${RED}✗ Configurația necesită atenție!${NC}"
fi

echo ""
echo "Pentru detalii suplimentare, verifică:"
echo "  - Kiali: kubectl port-forward svc/kiali -n istio-system 20001:20001"
echo "  - Grafana: kubectl port-forward svc/grafana -n monitoring 3000:80"
echo "  - ArgoCD: kubectl port-forward svc/argocd-server -n argocd 8080:443"
