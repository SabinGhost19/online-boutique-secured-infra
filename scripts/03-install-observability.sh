#!/bin/bash
# =============================================================================
# Script: 03-install-observability.sh
# Descriere: Instalează stack-ul de observabilitate pentru Istio
#            (Kiali, Prometheus, Grafana, Jaeger)
# =============================================================================

set -e

echo "=============================================="
echo "INSTALARE STACK OBSERVABILITATE"
echo "=============================================="

# Culori
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# =============================================================================
# PASUL 1: Instalare Prometheus
# =============================================================================
echo ""
echo ">>> [1/4] Instalare Prometheus..."

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install prometheus prometheus-community/prometheus \
    --namespace monitoring \
    --create-namespace \
    --values ../observability/prometheus-values.yaml \
    --wait --timeout 5m

echo -e "${GREEN}✓${NC} Prometheus instalat"

# =============================================================================
# PASUL 2: Instalare Grafana
# =============================================================================
echo ""
echo ">>> [2/4] Instalare Grafana..."

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install grafana grafana/grafana \
    --namespace monitoring \
    --values ../observability/grafana-values.yaml \
    --wait --timeout 5m

echo -e "${GREEN}✓${NC} Grafana instalat"

# Obține parola admin pentru Grafana
echo ""
echo -e "${YELLOW}Parola admin Grafana:${NC}"
kubectl get secret --namespace monitoring grafana -o jsonpath="{.data.admin-password}" | base64 --decode
echo ""

# =============================================================================
# PASUL 3: Instalare Jaeger
# =============================================================================
echo ""
echo ">>> [3/4] Instalare Jaeger (distributed tracing)..."

# Folosim manifestele oficiale Istio pentru Jaeger
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/addons/jaeger.yaml \
    -n monitoring || {
    echo "Fallback: Instalare Jaeger în istio-system..."
    kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.24/samples/addons/jaeger.yaml \
        -n istio-system
}

echo -e "${GREEN}✓${NC} Jaeger instalat"

# =============================================================================
# PASUL 4: Instalare Kiali
# =============================================================================
echo ""
echo ">>> [4/4] Instalare Kiali..."

helm repo add kiali https://kiali.org/helm-charts
helm repo update

# Instalează Kiali operator și CR
helm upgrade --install kiali-operator kiali/kiali-operator \
    --namespace kiali-operator \
    --create-namespace \
    --set cr.create=true \
    --set cr.namespace=istio-system \
    --values ../observability/kiali-values.yaml \
    --wait --timeout 5m

echo -e "${GREEN}✓${NC} Kiali instalat"

# =============================================================================
# VERIFICĂRI FINALE
# =============================================================================
echo ""
echo "=============================================="
echo "VERIFICARE INSTALARE OBSERVABILITATE"
echo "=============================================="

echo ""
echo ">>> Poduri în monitoring namespace:"
kubectl get pods -n monitoring

echo ""
echo ">>> Poduri Kiali:"
kubectl get pods -n istio-system -l app=kiali

echo ""
echo ">>> Servicii de observabilitate:"
kubectl get svc -n monitoring
kubectl get svc -n istio-system | grep -E "kiali|jaeger"

echo ""
echo "=============================================="
echo "ACCESARE SERVICII (port-forward)"
echo "=============================================="
echo ""
echo "Prometheus:"
echo "  kubectl port-forward svc/prometheus-server -n monitoring 9090:80"
echo "  Apoi accesează: http://localhost:9090"
echo ""
echo "Grafana:"
echo "  kubectl port-forward svc/grafana -n monitoring 3000:80"
echo "  Apoi accesează: http://localhost:3000"
echo "  User: admin, Parola: vezi mai sus"
echo ""
echo "Jaeger:"
echo "  kubectl port-forward svc/tracing -n istio-system 16686:80"
echo "  sau: kubectl port-forward svc/jaeger-query -n monitoring 16686:16686"
echo "  Apoi accesează: http://localhost:16686"
echo ""
echo "Kiali:"
echo "  kubectl port-forward svc/kiali -n istio-system 20001:20001"
echo "  Apoi accesează: http://localhost:20001"
echo ""

echo "=============================================="
echo -e "${GREEN}STACK OBSERVABILITATE INSTALAT CU SUCCES${NC}"
echo "=============================================="
echo ""
echo "Următorul pas: ./scripts/04-install-sealed-secrets.sh"
