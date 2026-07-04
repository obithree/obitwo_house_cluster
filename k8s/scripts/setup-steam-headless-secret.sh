#!/bin/bash
# Steam Headless Secret のセットアップスクリプト
#
# 使い方:
#   ./k8s/scripts/setup-steam-headless-secret.sh
#
# 事前準備:
#   kubectl が gaming namespace にアクセスできる状態にしておく

set -euo pipefail

NAMESPACE="gaming"
SECRET_NAME="steam-headless-secret"

echo "=== Steam Headless Secret セットアップ ==="
echo ""

# 既存のSecretを確認
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
  echo "[INFO] 既存のSecret '$SECRET_NAME' が見つかりました。上書きします。"
fi

# 入力プロンプト
read -rsp "NEKO_PASSWORD (noVNC 一般ユーザーパスワード): " NEKO_PASSWORD
echo ""

if [[ -z "$NEKO_PASSWORD" ]]; then
  echo "[ERROR] NEKO_PASSWORD は必須です。"
  exit 1
fi

read -rsp "NEKO_PASSWORD_ADMIN (noVNC 管理者パスワード): " NEKO_PASSWORD_ADMIN
echo ""

if [[ -z "$NEKO_PASSWORD_ADMIN" ]]; then
  echo "[ERROR] NEKO_PASSWORD_ADMIN は必須です。"
  exit 1
fi

# Namespaceがなければ作成
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Secretを作成 or 上書き
kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-literal=NEKO_PASSWORD="$NEKO_PASSWORD" \
  --from-literal=NEKO_PASSWORD_ADMIN="$NEKO_PASSWORD_ADMIN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "[OK] Secret '$SECRET_NAME' を namespace '$NAMESPACE' に設定しました。"
echo ""
echo "次のステップ: ArgoCDで steam-headless-prd をSyncしてください。"
