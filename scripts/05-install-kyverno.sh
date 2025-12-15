#!/bin/bash
# =============================================================================
# Script: 05-install-kyverno.sh
# Descriere: Instalează Kyverno Policy Engine și aplică politicile de securitate
# =============================================================================

set -e

echo "=============================================="
echo "INSTALARE KYVERNO POLICY ENGINE"
echo "=============================================="

# Culori
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Versiune
KYVERNO_VERSION="3.3.3"

# =============================================================================
# PASUL 1: Instalare Kyverno
# =============================================================================
echo ""
echo ">>> [1/3] Instalare Kyverno..."

helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

# Instalare cu High Availability pentru producție
helm upgrade --install kyverno kyverno/kyverno \
    --namespace kyverno \
    --create-namespace \
    --version ${KYVERNO_VERSION} \
    --values ../kyverno/kyverno-values.yaml \
    --wait --timeout 5m

echo -e "${GREEN}✓${NC} Kyverno instalat"

# Așteaptă ca toate podurile să fie ready
echo ""
echo ">>> Așteptare poduri Kyverno să fie ready..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/instance=kyverno \
    -n kyverno --timeout=300s

# =============================================================================
# PASUL 2: Verificare CRDs
# =============================================================================
echo ""
echo ">>> [2/3] Verificare CRDs Kyverno..."
kubectl get crds | grep kyverno

# =============================================================================
# PASUL 3: Aplicare politici de securitate
# =============================================================================
echo ""
echo ">>> [3/3] Aplicare politici de securitate..."

# Aplică politicile una câte una pentru debugging mai ușor
echo ""
echo "Aplicare: Pod Security Restricted..."
kubectl apply -f ../kyverno/policies/pod-security-restricted.yaml

echo "Aplicare: Require Resource Limits..."
kubectl apply -f ../kyverno/policies/require-resource-limits.yaml

echo "Aplicare: Restrict Image Registries..."
kubectl apply -f ../kyverno/policies/restrict-registries.yaml

echo "Aplicare: Require Labels..."
kubectl apply -f ../kyverno/policies/require-labels.yaml

echo "Aplicare: Istio Exceptions..."
kubectl apply -f ../kyverno/policies/istio-exceptions.yaml

echo ""
echo -e "${GREEN}✓${NC} Toate politicile aplicate"

# =============================================================================
# VERIFICARE POLITICI
# =============================================================================
echo ""
echo "=============================================="
echo "VERIFICARE POLITICI KYVERNO"
echo "=============================================="

echo ""
echo ">>> ClusterPolicies instalate:"
kubectl get clusterpolicies

echo ""
echo ">>> Status politici:"
kubectl get clusterpolicies -o custom-columns=\
'NAME:.metadata.name,READY:.status.ready,MESSAGE:.status.conditions[0].message'

echo ""
echo ">>> Poduri Kyverno:"
kubectl get pods -n kyverno

# =============================================================================
# TEST POLITICI
# =============================================================================
echo ""
echo "=============================================="
echo "TEST POLITICI (opțional)"
echo "=============================================="
echo ""
echo "Pentru a testa că politicile funcționează, încearcă să creezi un pod"
echo "care încalcă politicile:"
echo ""
echo "# Acest pod ar trebui să fie BLOCAT (rulează ca root):"
echo 'kubectl run test-root --image=nginx --restart=Never -n develop --dry-run=server'
echo ""
echo "# Acest pod ar trebui să fie ACCEPTAT (dacă respectă politicile):"
echo 'kubectl run test-valid --image=nginx --restart=Never -n develop \'
echo '    --overrides='"'"'{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000},"containers":[{"name":"test","image":"nginx","securityContext":{"allowPrivilegeEscalation":false},"resources":{"requests":{"cpu":"100m","memory":"64Mi"},"limits":{"cpu":"200m","memory":"128Mi"}}}]}}'"'"' \'
echo '    --dry-run=server'
echo ""

echo "=============================================="
echo -e "${GREEN}KYVERNO INSTALAT CU SUCCES${NC}"
echo "=============================================="
echo ""
echo -e "${YELLOW}NOTĂ:${NC} Politicile sunt în mod AUDIT pentru început."
echo "După testare, schimbă validationFailureAction la 'Enforce'."
echo ""
echo "Următorul pas: ./scripts/06-install-argocd.sh"
