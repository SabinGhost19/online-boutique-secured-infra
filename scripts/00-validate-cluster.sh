#!/bin/bash
# =============================================================================
# Script: 00-validate-cluster.sh
# Descriere: Validează starea clusterului Kubernetes și instalarea Calico
# Autor: Ghid implementare teză licență
# =============================================================================

set -e

echo "=============================================="
echo "VALIDARE CLUSTER KUBERNETES ȘI CALICO CNI"
echo "=============================================="

# Culori pentru output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Funcție pentru verificări
check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 este instalat"
        return 0
    else
        echo -e "${RED}✗${NC} $1 NU este instalat"
        return 1
    fi
}

check_resource() {
    if kubectl get $1 $2 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 $2 există"
        return 0
    else
        echo -e "${RED}✗${NC} $1 $2 NU există"
        return 1
    fi
}

echo ""
echo ">>> Verificare tool-uri necesare..."
check_command kubectl
check_command helm
check_command git
check_command curl

echo ""
echo ">>> Verificare versiune Kubernetes..."
kubectl version --short 2>/dev/null || kubectl version
echo ""

echo ">>> Verificare noduri cluster..."
kubectl get nodes -o wide
echo ""

echo ">>> Verificare Calico CNI..."

# Verifică dacă Calico este instalat (operator-based sau manifest-based)
echo "Căutare poduri Calico..."

# Operator-based installation
if kubectl get namespace tigera-operator &> /dev/null; then
    echo -e "${GREEN}✓${NC} Calico instalat via Tigera Operator"
    echo ""
    echo "Status Tigera Operator:"
    kubectl get pods -n tigera-operator
    echo ""
    echo "Status Calico System:"
    kubectl get pods -n calico-system
    echo ""
    echo "Tigera Status:"
    kubectl get tigerastatus 2>/dev/null || echo "tigerastatus CRD not found"
fi

# Manifest-based installation (kube-system)
if kubectl get pods -n kube-system -l k8s-app=calico-node &> /dev/null; then
    CALICO_PODS=$(kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers 2>/dev/null | wc -l)
    if [ "$CALICO_PODS" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} Calico instalat în kube-system (manifest-based)"
        echo ""
        echo "Calico Node pods:"
        kubectl get pods -n kube-system -l k8s-app=calico-node
        echo ""
        echo "Calico Kube Controllers:"
        kubectl get pods -n kube-system -l k8s-app=calico-kube-controllers
    fi
fi

echo ""
echo ">>> Verificare versiune Calico..."
# Încearcă să obțină versiunea din diferite locații
CALICO_VERSION=""

# Metoda 1: Din deployment calico-kube-controllers în calico-system
if kubectl get deployment -n calico-system calico-kube-controllers &> /dev/null; then
    CALICO_VERSION=$(kubectl get deployment -n calico-system calico-kube-controllers -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2)
fi

# Metoda 2: Din daemonset calico-node în kube-system
if [ -z "$CALICO_VERSION" ]; then
    if kubectl get daemonset -n kube-system calico-node &> /dev/null; then
        CALICO_VERSION=$(kubectl get daemonset -n kube-system calico-node -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2)
    fi
fi

if [ -n "$CALICO_VERSION" ]; then
    echo -e "${GREEN}✓${NC} Versiune Calico: $CALICO_VERSION"
else
    echo -e "${YELLOW}!${NC} Nu s-a putut determina versiunea Calico"
fi

echo ""
echo ">>> Verificare că toate nodurile Calico sunt Ready..."
# Verifică în ambele namespace-uri posibile
for NS in calico-system kube-system; do
    if kubectl get pods -n $NS -l k8s-app=calico-node &> /dev/null; then
        NOT_READY=$(kubectl get pods -n $NS -l k8s-app=calico-node --no-headers 2>/dev/null | grep -v "Running" | wc -l)
        TOTAL=$(kubectl get pods -n $NS -l k8s-app=calico-node --no-headers 2>/dev/null | wc -l)
        if [ "$NOT_READY" -eq 0 ] && [ "$TOTAL" -gt 0 ]; then
            echo -e "${GREEN}✓${NC} Toate cele $TOTAL calico-node pods sunt Running în $NS"
        elif [ "$TOTAL" -gt 0 ]; then
            echo -e "${RED}✗${NC} $NOT_READY din $TOTAL calico-node pods nu sunt Running în $NS"
        fi
    fi
done

echo ""
echo ">>> Verificare suport NetworkPolicy..."
echo "Creez un test rapid pentru NetworkPolicy..."

# Creează namespace de test
kubectl create namespace netpol-test --dry-run=client -o yaml | kubectl apply -f -

# Creează o NetworkPolicy de test
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: test-network-policy
  namespace: netpol-test
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

# Verifică că s-a creat
if kubectl get networkpolicy test-network-policy -n netpol-test &> /dev/null; then
    echo -e "${GREEN}✓${NC} NetworkPolicy a fost creată cu succes"
    echo -e "${GREEN}✓${NC} CNI-ul suportă NetworkPolicies!"
else
    echo -e "${RED}✗${NC} NetworkPolicy NU a putut fi creată"
    echo -e "${RED}✗${NC} CNI-ul poate să NU suporte NetworkPolicies!"
fi

# Curăță
kubectl delete namespace netpol-test --ignore-not-found

echo ""
echo ">>> Verificare NGINX Ingress Controller..."
if kubectl get namespace ingress-nginx &> /dev/null; then
    echo -e "${GREEN}✓${NC} Namespace ingress-nginx există"
    kubectl get pods -n ingress-nginx
    kubectl get svc -n ingress-nginx
else
    echo -e "${YELLOW}!${NC} Namespace ingress-nginx nu există"
    echo "  Verifică alt namespace pentru Ingress Controller..."
    kubectl get pods -A | grep -i ingress || echo "Nu s-a găsit niciun Ingress Controller"
fi

echo ""
echo ">>> Verificare cloudflared..."
for NS in cloudflare cloudflare-system cloudflared default; do
    if kubectl get pods -n $NS -l app=cloudflared &> /dev/null 2>&1; then
        CLOUDFLARED_PODS=$(kubectl get pods -n $NS -l app=cloudflared --no-headers 2>/dev/null | wc -l)
        if [ "$CLOUDFLARED_PODS" -gt 0 ]; then
            echo -e "${GREEN}✓${NC} cloudflared găsit în namespace $NS"
            kubectl get pods -n $NS -l app=cloudflared
            break
        fi
    fi
done

echo ""
echo ">>> Verificare resurse disponibile..."
kubectl top nodes 2>/dev/null || echo "Metrics server nu este instalat (opțional)"

echo ""
echo ">>> Verificare StorageClass disponibile..."
kubectl get storageclass

echo ""
echo "=============================================="
echo "SUMAR VALIDARE"
echo "=============================================="
echo ""
echo "Dacă toate verificările au trecut (✓), puteți continua cu instalarea."
echo "Dacă există erori (✗), rezolvați-le înainte de a continua."
echo ""
echo "Următorul pas: ./scripts/01-create-namespaces.sh"
