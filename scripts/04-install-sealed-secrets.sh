#!/bin/bash
# =============================================================================
# Script: 04-install-sealed-secrets.sh
# Descriere: Instalează Sealed Secrets pentru managementul securizat al secretelor
# =============================================================================

set -e

echo "=============================================="
echo "INSTALARE SEALED SECRETS"
echo "=============================================="

# Culori
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Versiunea Sealed Secrets
SEALED_SECRETS_VERSION="2.14.2"
KUBESEAL_VERSION="0.24.5"

# =============================================================================
# PASUL 1: Instalare Sealed Secrets Controller
# =============================================================================
echo ""
echo ">>> [1/3] Instalare Sealed Secrets Controller..."

helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

helm upgrade --install sealed-secrets-controller sealed-secrets/sealed-secrets \
    --namespace kube-system \
    --version ${SEALED_SECRETS_VERSION} \
    --values ../sealed-secrets/sealed-secrets-values.yaml \
    --wait

echo -e "${GREEN}✓${NC} Sealed Secrets Controller instalat"

# Așteaptă ca controller-ul să fie ready
echo ""
echo ">>> Așteptare controller să fie ready..."
kubectl wait --for=condition=available deployment/sealed-secrets-controller \
    -n kube-system --timeout=120s

# =============================================================================
# PASUL 2: Instalare kubeseal CLI
# =============================================================================
echo ""
echo ">>> [2/3] Verificare/Instalare kubeseal CLI..."

if command -v kubeseal &> /dev/null; then
    echo -e "${GREEN}✓${NC} kubeseal este deja instalat"
    kubeseal --version
else
    echo "Instalare kubeseal ${KUBESEAL_VERSION}..."
    
    # Detectează arhitectura
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        arm64) ARCH="arm64" ;;
    esac
    
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    # Descarcă și instalează
    wget -q "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-${OS}-${ARCH}.tar.gz" \
        -O /tmp/kubeseal.tar.gz
    
    tar -xzf /tmp/kubeseal.tar.gz -C /tmp kubeseal
    
    # Instalează (poate necesita sudo)
    if [ -w /usr/local/bin ]; then
        mv /tmp/kubeseal /usr/local/bin/kubeseal
        chmod +x /usr/local/bin/kubeseal
    else
        echo -e "${YELLOW}!${NC} Necesită sudo pentru instalare în /usr/local/bin"
        sudo mv /tmp/kubeseal /usr/local/bin/kubeseal
        sudo chmod +x /usr/local/bin/kubeseal
    fi
    
    rm -f /tmp/kubeseal.tar.gz
    
    echo -e "${GREEN}✓${NC} kubeseal instalat"
    kubeseal --version
fi

# =============================================================================
# PASUL 3: Verificare și export public key
# =============================================================================
echo ""
echo ">>> [3/3] Export public key pentru backup..."

mkdir -p ../sealed-secrets/keys

# Obține cheia publică
kubeseal --fetch-cert \
    --controller-name=sealed-secrets-controller \
    --controller-namespace=kube-system \
    > ../sealed-secrets/keys/sealed-secrets-public-key.pem

echo -e "${GREEN}✓${NC} Cheia publică exportată în sealed-secrets/keys/sealed-secrets-public-key.pem"

# =============================================================================
# EXEMPLU: Cum să creezi un SealedSecret
# =============================================================================
echo ""
echo "=============================================="
echo "EXEMPLU: CREARE SEALEDSECRET"
echo "=============================================="
echo ""
echo "1. Creează un secret normal (dry-run):"
echo '   kubectl create secret generic my-secret \'
echo '       --namespace=develop \'
echo '       --from-literal=username=admin \'
echo '       --from-literal=password=supersecret \'
echo '       --dry-run=client -o yaml > my-secret.yaml'
echo ""
echo "2. Sigilează secretul:"
echo '   kubeseal --format=yaml \'
echo '       --controller-name=sealed-secrets-controller \'
echo '       --controller-namespace=kube-system \'
echo '       < my-secret.yaml > my-sealed-secret.yaml'
echo ""
echo "3. Aplică sealed secret (sigur pentru Git):"
echo '   kubectl apply -f my-sealed-secret.yaml'
echo ""
echo "4. Verifică că secretul a fost creat:"
echo '   kubectl get secret my-secret -n develop'
echo ""

# Creează un exemplu
echo ">>> Creare exemplu de SealedSecret..."

# Creează directorul pentru exemple
mkdir -p ../sealed-secrets/examples

# Creează secret de test
cat <<EOF > /tmp/example-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: example-sealed-secret
  namespace: develop
type: Opaque
stringData:
  username: admin
  password: example-password-change-me
EOF

# Sigilează
kubeseal --format=yaml \
    --controller-name=sealed-secrets-controller \
    --controller-namespace=kube-system \
    < /tmp/example-secret.yaml \
    > ../sealed-secrets/examples/example-sealed-secret.yaml

rm /tmp/example-secret.yaml

echo -e "${GREEN}✓${NC} Exemplu creat în sealed-secrets/examples/example-sealed-secret.yaml"

# =============================================================================
# VERIFICARE FINALĂ
# =============================================================================
echo ""
echo "=============================================="
echo "VERIFICARE INSTALARE"
echo "=============================================="

echo ""
echo ">>> Sealed Secrets Controller:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets

echo ""
echo ">>> Versiune controller:"
kubectl get deployment sealed-secrets-controller -n kube-system \
    -o jsonpath='{.spec.template.spec.containers[0].image}'
echo ""

echo ""
echo "=============================================="
echo -e "${GREEN}SEALED SECRETS INSTALAT CU SUCCES${NC}"
echo "=============================================="
echo ""
echo -e "${YELLOW}IMPORTANT:${NC} Fă backup la cheia privată pentru disaster recovery:"
echo "kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-master-key-backup.yaml"
echo ""
echo "Următorul pas: ./scripts/05-install-kyverno.sh"
