#!/bin/bash
# Grafana Admin パスワード Secret のセットアップスクリプト
#
# 使い方:
#   ./k8s/scripts/setup-grafana-secret.sh
#
# 事前準備:
#   kubectl が monitoring namespace にアクセスできる状態にしておく

set -euo pipefail

NAMESPACE="monitoring"
SECRET_NAME="grafana-admin-secret"

echo "=== Grafana Admin Secret セットアップ ==="
echo ""

# 既存のSecretを確認
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
  echo "[INFO] 既存のSecret '$SECRET_NAME' が見つかりました。上書きします。"
fi

# 入力プロンプト
read -rsp "Grafana Admin Password: " ADMIN_PASSWORD
echo ""

if [[ -z "$ADMIN_PASSWORD" ]]; then
  echo "[ERROR] パスワードは必須です。"
  exit 1
fi

# Namespaceがなければ作成
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Secretを作成 or 上書き
kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-literal=admin-password="$ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "[OK] Secret '$SECRET_NAME' を namespace '$NAMESPACE' に設定しました。"
echo ""
echo "次のステップ: ArgoCDで monitoring-grafana をSyncしてください。"
