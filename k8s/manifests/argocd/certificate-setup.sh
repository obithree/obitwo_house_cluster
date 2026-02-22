#!/bin/bash
# ArgoCD用のself-signed証明書を作成するスクリプト

set -e

DOMAIN="${1:-argocd.home.local}"
DAYS="${2:-365}"
CERT_DIR="./certs"

echo "📝 Creating self-signed certificate for: $DOMAIN"
echo "📅 Validity period: $DAYS days"

# ディレクトリを作成
mkdir -p "$CERT_DIR"

# 秘密鍵を生成
openssl genrsa -out "$CERT_DIR/argocd.key" 2048

# 証明書を生成
openssl req -x509 -new \
  -key "$CERT_DIR/argocd.key" \
  -out "$CERT_DIR/argocd.crt" \
  -days "$DAYS" \
  -subj "/CN=$DOMAIN" \
  -addext "subjectAltName=DNS:$DOMAIN"

echo "✅ Certificate created successfully"
echo "   Key: $CERT_DIR/argocd.key"
echo "   Cert: $CERT_DIR/argocd.crt"

# Kubernetes Secret を作成
echo ""
echo "🔐 Creating Kubernetes Secret..."
kubectl create secret tls argocd-tls-self-signed \
  --cert="$CERT_DIR/argocd.crt" \
  --key="$CERT_DIR/argocd.key" \
  -n argocd \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Secret created successfully"
echo ""
echo "🚀 Applying Ingress configuration..."
kubectl apply -f k8s/manifests/argocd/ingress.yaml

echo "✅ Ingress applied successfully"
echo ""
echo "📍 Access ArgoCD at: https://$DOMAIN"
echo ""
echo "⚠️  Note: If using nip.io, use the IP-based domain instead"
echo "   Example: https://argocd.192.168.1.10.nip.io"
