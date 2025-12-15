#!/bin/bash
# =============================================================================
# Script: 01-create-namespaces.sh
# Descriere: Creează toate namespace-urile necesare pentru proiect
# =============================================================================

set -e

echo "=============================================="
echo "CREARE NAMESPACE-URI"
echo "=============================================="

# Aplică toate namespace-urile
kubectl apply -f ../namespaces/

echo ""
echo ">>> Verificare namespace-uri create..."
kubectl get namespaces | grep -E "istio-system|develop|prod|kyverno|argocd|monitoring"

echo ""
echo ">>> Namespace-uri cu label-uri:"
kubectl get namespaces --show-labels | grep -E "istio-system|develop|prod"

echo ""
echo "=============================================="
echo "NAMESPACE-URI CREATE CU SUCCES"
echo "=============================================="
echo ""
echo "Următorul pas: ./scripts/02-install-istio.sh"
