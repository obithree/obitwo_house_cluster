#!/bin/bash
set -e

ENV=${1:-prd}

echo "==> [1/3] ArgoCD Helm リポジトリを追加"
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "==> [2/3] ArgoCD をインストール (env: ${ENV})"
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set global.nodeSelector."node-role"=worker \
  --set server.extraArgs[0]="--insecure" \
  --wait

echo "==> [3/3] ArgoCD Server の起動を待機"
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd

echo ""
echo "Deploy complete!"
echo "ArgoCD 初期パスワード: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "App-of-Apps を適用する場合:"
echo "  kubectl apply -f k8s/argocd/bootstrap/app-of-apps-${ENV}.yaml"
