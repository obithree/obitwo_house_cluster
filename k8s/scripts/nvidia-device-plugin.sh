#!/bin/bash
# NVIDIA Device Plugin を k8s クラスターにデプロイするスクリプト
set -e

MANIFEST="${BASH_SOURCE%/*}/../manifests/nvidia-device-plugin/daemonset.yaml"

echo "==> NVIDIA Device Plugin をデプロイ"
kubectl apply -f "${MANIFEST}"

echo "==> NVIDIA Device Plugin の起動を待機中..."
kubectl rollout status daemonset/nvidia-device-plugin-daemonset \
  -n kube-system --timeout=120s

echo ""
echo "Deploy complete!"
echo ""
echo "GPU リソースの確認:"
echo "  kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.capacity.nvidia\.com/gpu'"

echo ""
echo "Deploy complete!"
echo ""
echo "GPU リソースの確認:"
echo "  kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.capacity.nvidia\.com/gpu'"
