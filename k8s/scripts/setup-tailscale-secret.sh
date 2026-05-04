#!/bin/bash
# Tailscale Operator OAuth Secretのセットアップスクリプト
#
# 使い方:
#   ./k8s/scripts/setup-tailscale-secret.sh
#
# 事前準備:
#   https://login.tailscale.com/admin/settings/oauth でOAuthクライアントを作成し
#   client_id と client_secret を取得しておく

set -euo pipefail

NAMESPACE="tailscale"
SECRET_NAME="tailscale-operator-oauth"

echo "=== Tailscale Operator OAuth Secret セットアップ ==="
echo ""

# 既存のSecretを確認
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
  echo "[INFO] 既存のSecret '$SECRET_NAME' が見つかりました。上書きします。"
fi

# 入力プロンプト
read -rp "Tailscale OAuth Client ID: " CLIENT_ID
read -rsp "Tailscale OAuth Client Secret: " CLIENT_SECRET
echo ""

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
  echo "[ERROR] Client ID と Client Secret は必須です。"
  exit 1
fi

# Namespaceがなければ作成
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Secretを作成 or 上書き
kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-literal=client_id="$CLIENT_ID" \
  --from-literal=client_secret="$CLIENT_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "[OK] Secret '$SECRET_NAME' を namespace '$NAMESPACE' に設定しました。"
echo ""
echo "次のステップ: ArgoCDでtailscale-operator-prdをSyncしてください。"
echo "  Operatorが起動したら Tailscale Admin Console でデバイスが登録されます。"
