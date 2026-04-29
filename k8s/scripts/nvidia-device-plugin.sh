#!/bin/bash
# NVIDIA Device Plugin を k8s クラスターにデプロイするスクリプト
set -e

PLUGIN_VERSION="${1:-v0.17.0}"
MANIFEST_URL="https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/${PLUGIN_VERSION}/deployments/static/nvidia-device-plugin.yml"

echo "==> NVIDIA Device Plugin のデプロイ (version: ${PLUGIN_VERSION})"

# 既存のデプロイを確認
if kubectl get daemonset -n kube-system nvidia-device-plugin-daemonset &>/dev/null; then
  echo "    既存の NVIDIA Device Plugin を更新します"
else
  echo "    NVIDIA Device Plugin を新規デプロイします"
fi

kubectl apply -f "${MANIFEST_URL}"

echo "==> PC ノード (node-type=pc) のみ・nvidiagpu 戦略でパッチ適用"
# auto 戦略は containerd のデフォルトランタイムを nvidia にする必要があるため
# nvidiagpu 戦略（containerd の nvidia ランタイム経由）を明示指定
kubectl patch daemonset nvidia-device-plugin-daemonset \
  -n kube-system \
  --type=merge \
  -p '{
    "spec": {
      "template": {
        "spec": {
          "nodeSelector": {"node-type": "pc"},
          "containers": [{
            "name": "nvidia-device-plugin-ctr",
            "args": ["--device-discovery-strategy=nvidiagpu"]
          }]
        }
      }
    }
  }'

echo "==> NVIDIA Device Plugin の起動を待機中..."
kubectl rollout status daemonset/nvidia-device-plugin-daemonset \
  -n kube-system --timeout=120s

echo ""
echo "Deploy complete!"
echo ""
echo "GPU リソースの確認:"
echo "  kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.capacity.nvidia\.com/gpu'"
