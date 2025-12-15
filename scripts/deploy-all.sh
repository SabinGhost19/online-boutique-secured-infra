#!/bin/bash
# =============================================================================
# Script: deploy-all.sh
# Descriere: Script master care execută toți pașii de deployment
# =============================================================================
# UTILIZARE:
#   ./deploy-all.sh              # Deployment complet
#   ./deploy-all.sh --dry-run    # Doar afișează ce ar face
#   ./deploy-all.sh --skip-argocd # Skip ArgoCD (pentru deploy manual)
# =============================================================================

set -e

echo "=============================================="
echo "DEPLOYMENT COMPLET - ONLINE BOUTIQUE"
echo "Cu Istio, Kyverno, ArgoCD și Security Policies"
echo "=============================================="

# Culori
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Parse arguments
DRY_RUN=false
SKIP_ARGOCD=false

for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
        --skip-argocd)
            SKIP_ARGOCD=true
            ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}DRY RUN MODE - Nu se vor face modificări${NC}"
    echo ""
fi

# Funcție pentru a rula un script
run_step() {
    local step_num=$1
    local step_name=$2
    local script=$3
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}PASUL $step_num: $step_name${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        echo "Would run: ./$script"
    else
        chmod +x "./$script"
        "./$script"
    fi
    
    echo ""
    echo -e "${GREEN}✓ Pasul $step_num completat${NC}"
    echo ""
    
    if [ "$DRY_RUN" = false ]; then
        read -p "Apasă ENTER pentru a continua la pasul următor (sau Ctrl+C pentru a opri)..."
    fi
}

# =============================================================================
# CONFIRMARE
# =============================================================================
echo ""
echo "Acest script va:"
echo "  1. Valida cluster-ul și Calico CNI"
echo "  2. Crea namespace-urile necesare"
echo "  3. Instala Istio Service Mesh"
echo "  4. Instala stack-ul de observabilitate (Prometheus, Grafana, Kiali, Jaeger)"
echo "  5. Instala Sealed Secrets"
echo "  6. Instala Kyverno și politicile de securitate"
if [ "$SKIP_ARGOCD" = false ]; then
    echo "  7. Instala ArgoCD"
fi
echo "  8. Deploya Online Boutique în develop"
echo "  9. Aplica politicile de securitate (NetworkPolicies, Istio policies)"
echo " 10. Valida configurația"
echo ""

if [ "$DRY_RUN" = false ]; then
    read -p "Continuă? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Anulat."
        exit 0
    fi
fi

# =============================================================================
# EXECUȚIE
# =============================================================================

# Pasul 0: Validare cluster
run_step "0" "Validare Cluster și Calico" "00-validate-cluster.sh"

# Pasul 1: Creare namespace-uri
run_step "1" "Creare Namespace-uri" "01-create-namespaces.sh"

# Pasul 2: Instalare Istio
run_step "2" "Instalare Istio Service Mesh" "02-install-istio.sh"

# Pasul 3: Instalare Observabilitate
run_step "3" "Instalare Stack Observabilitate" "03-install-observability.sh"

# Pasul 4: Instalare Sealed Secrets
run_step "4" "Instalare Sealed Secrets" "04-install-sealed-secrets.sh"

# Pasul 5: Instalare Kyverno
run_step "5" "Instalare Kyverno Policy Engine" "05-install-kyverno.sh"

# Pasul 6: Instalare ArgoCD
if [ "$SKIP_ARGOCD" = false ]; then
    run_step "6" "Instalare ArgoCD" "06-install-argocd.sh"
else
    echo -e "${YELLOW}Skipping ArgoCD (--skip-argocd flag)${NC}"
fi

# Pasul 7: Deploy Online Boutique
run_step "7" "Deploy Online Boutique" "07-deploy-online-boutique.sh"

# Pasul 8: Aplicare Security Policies
run_step "8" "Aplicare Security Policies" "08-apply-security-policies.sh"

# Pasul 9: Validare
run_step "9" "Validare Securitate" "09-validate-security.sh"

# =============================================================================
# SUMAR FINAL
# =============================================================================
echo ""
echo "=============================================="
echo -e "${GREEN}DEPLOYMENT COMPLET!${NC}"
echo "=============================================="
echo ""
echo "Componente instalate:"
echo "  ✓ Istio Service Mesh cu mTLS strict"
echo "  ✓ Kiali, Prometheus, Grafana, Jaeger"
echo "  ✓ Sealed Secrets pentru secret management"
echo "  ✓ Kyverno cu Pod Security Standards"
if [ "$SKIP_ARGOCD" = false ]; then
    echo "  ✓ ArgoCD pentru GitOps"
fi
echo "  ✓ Online Boutique în namespace develop"
echo "  ✓ NetworkPolicies (default deny + explicit allow)"
echo "  ✓ Istio AuthorizationPolicies"
echo ""
echo "=============================================="
echo "ACCES RAPID"
echo "=============================================="
echo ""
echo "Online Boutique:"
echo "  kubectl port-forward svc/frontend -n develop 8080:80"
echo "  → http://localhost:8080"
echo ""
echo "Kiali (Service Mesh visualization):"
echo "  kubectl port-forward svc/kiali -n istio-system 20001:20001"
echo "  → http://localhost:20001"
echo ""
echo "Grafana (Dashboards):"
echo "  kubectl port-forward svc/grafana -n monitoring 3000:80"
echo "  → http://localhost:3000"
echo ""
if [ "$SKIP_ARGOCD" = false ]; then
    echo "ArgoCD:"
    echo "  kubectl port-forward svc/argocd-server -n argocd 8443:443"
    echo "  → https://localhost:8443"
    echo "  Password: cat argocd/.admin-password"
    echo ""
fi
echo "=============================================="
echo "NEXT STEPS"
echo "=============================================="
echo ""
echo "1. Explorează aplicația în browser"
echo "2. Vizualizează mesh-ul în Kiali"
echo "3. Verifică metrici în Grafana"
echo "4. Pentru producție, deploy în namespace 'prod'"
echo "5. Configurează Ingress și Cloudflare Tunnel"
echo ""
