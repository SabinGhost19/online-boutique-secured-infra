#!/bin/bash
# =============================================================================
# Script: 06-install-argocd.sh
# Descriere: Instalează ArgoCD pentru GitOps workflow
# =============================================================================

set -e

echo "=============================================="
echo "INSTALARE ARGOCD"
echo "=============================================="

# Culori
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Versiune
ARGOCD_VERSION="7.7.10"

# =============================================================================
# PASUL 1: Instalare ArgoCD
# =============================================================================
echo ""
echo ">>> [1/4] Instalare ArgoCD..."

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --create-namespace \
    --version ${ARGOCD_VERSION} \
    --values ../argocd/argocd-values.yaml \
    --wait --timeout 10m

echo -e "${GREEN}✓${NC} ArgoCD instalat"

# Așteaptă ca toate componentele să fie ready
echo ""
echo ">>> Așteptare componente ArgoCD să fie ready..."
kubectl wait --for=condition=available deployment --all \
    -n argocd --timeout=300s

# =============================================================================
# PASUL 2: Obține parola admin
# =============================================================================
echo ""
echo ">>> [2/4] Obținere parola admin..."

ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo -e "${YELLOW}=============================================="
echo "CREDENȚIALE ARGOCD"
echo "=============================================="
echo "Username: admin"
echo "Password: ${ARGOCD_PASSWORD}"
echo "==============================================${NC}"
echo ""

# Salvează parola într-un fișier (pentru conveniență în development)
echo "${ARGOCD_PASSWORD}" > ../argocd/.admin-password
chmod 600 ../argocd/.admin-password
echo "Parola salvată în argocd/.admin-password"

# =============================================================================
# PASUL 3: Instalare ArgoCD CLI
# =============================================================================
echo ""
echo ">>> [3/4] Verificare/Instalare ArgoCD CLI..."

if command -v argocd &> /dev/null; then
    echo -e "${GREEN}✓${NC} argocd CLI este deja instalat"
    argocd version --client
else
    echo "Instalare ArgoCD CLI..."
    
    # Detectează OS
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
    esac
    
    # Descarcă
    curl -sSL -o /tmp/argocd "https://github.com/argoproj/argo-cd/releases/latest/download/argocd-${OS}-${ARCH}"
    
    # Instalează
    if [ -w /usr/local/bin ]; then
        install -m 555 /tmp/argocd /usr/local/bin/argocd
    else
        sudo install -m 555 /tmp/argocd /usr/local/bin/argocd
    fi
    
    rm /tmp/argocd
    
    echo -e "${GREEN}✓${NC} argocd CLI instalat"
    argocd version --client
fi

# =============================================================================
# PASUL 4: Creare Projects și configurare RBAC
# =============================================================================
echo ""
echo ">>> [4/4] Creare ArgoCD Projects..."

# Aplică AppProjects
kubectl apply -f ../argocd/projects/

echo -e "${GREEN}✓${NC} ArgoCD Projects create"

# =============================================================================
# VERIFICARE FINALĂ
# =============================================================================
echo ""
echo "=============================================="
echo "VERIFICARE INSTALARE ARGOCD"
echo "=============================================="

echo ""
echo ">>> Poduri ArgoCD:"
kubectl get pods -n argocd

echo ""
echo ">>> Servicii ArgoCD:"
kubectl get svc -n argocd

echo ""
echo ">>> ArgoCD Projects:"
kubectl get appprojects -n argocd

# =============================================================================
# INSTRUCȚIUNI ACCES
# =============================================================================
echo ""
echo "=============================================="
echo "ACCESARE ARGOCD"
echo "=============================================="
echo ""
echo "Opțiunea 1: Port-forward (pentru development)"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Apoi accesează: https://localhost:8080"
echo ""
echo "Opțiunea 2: Login via CLI"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443 &"
echo "  argocd login localhost:8080 --username admin --password '${ARGOCD_PASSWORD}' --insecure"
echo ""
echo "Opțiunea 3: Ingress (pentru producție)"
echo "  Configurează Ingress în argocd-values.yaml și re-aplică"
echo ""

echo "=============================================="
echo -e "${GREEN}ARGOCD INSTALAT CU SUCCES${NC}"
echo "=============================================="
echo ""
echo "Următorii pași:"
echo "1. Configurează repository-ul Git în ArgoCD"
echo "2. Aplică ApplicationSets pentru Online Boutique"
echo ""
echo "Comenzi utile:"
echo "  # Adaugă repository Git"
echo "  argocd repo add https://github.com/YOUR-ORG/gitops-repo.git"
echo ""
echo "  # Listează aplicații"
echo "  argocd app list"
echo ""
echo "  # Sync aplicație"
echo "  argocd app sync <app-name>"
