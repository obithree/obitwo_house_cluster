# Helm Charts for ArgoCD

このディレクトリには、ArgoCD で管理される Helm チャートが含まれています。

## ディレクトリ構成

```
k8s/
├── charts/                           # Helmチャート
│   ├── ollama/
│   │   ├── Chart.yaml
│   │   ├──.yaml`: デフォルト設定
  - `values-dev.yaml`: 開発環境用設定（NodePort、GPU有効）
  - `values-prd.yaml`: 本番環境用設定（ClusterIP、大容量ストレージ）

### Open WebUI
Ollama 用 Web インターフェース

- **Chart パス**: `k8s/charts/open-webui`
- **Values ファイル**:
  - `values.yaml`: デフォルト設定
  - `values-dev.yaml`: 開発環境用設定（NodePort、シングルレプリカ）
  - `values-prd.yaml`: 本番環境用設定（ClusterIP、マルチレプリカ）
└── argocd/
    ├── bootstrap/                    # App of Apps定義
    │   ├── app-of-apps-dev.yaml
    │   └── app-of-apps-prd.yaml
    └── applications/                 # 個別のApplication定義
        ├── dev/
        │   ├── ollama.yaml
        │   └── open-webui.yaml
        └── prd/
            ├── ollama.yaml
            └── open-webui.yaml
```

## チャート一覧

### Ollama
AI モデルランタイム Ollama のデプロイメント

- **Chart パス**: `k8s/charts/ollama`
- **Values ファイル**:
  - `values-dev.yaml`: 開発環境用設定
  - `values-prd.yaml`: 本番環境用設定

### Open WebUI
Ollama 用 Web インターフェース

- **Chart パス**: `k8s/charts/open-webui`
- **Values ファイル**:
  - `values-dev.yaml`: 開発環境用設定
  - `values-prd.yaml`: 本番環境用設定

## ローカルでの検証

### Helm テンプレートの検証

```bash
# Ollama (dev)
helm template ollama ./k8s/charts/ollama -f ./k8s/charts/ollama/values-dev.yaml

# Open WebUI (dev)
helm template open-webui ./k8s/charts/open-webui -f ./k8s/charts/open-webui/values-dev.yaml
```

### ローカルインストール

```bash
# Ollama (dev)
helm install ollama ./k8s/charts/ollama -f ./k8s/charts/ollama/values-dev.yaml

# Open WebUI (dev)
helm install open-webui ./k8s/charts/open-webui -f ./k8s/charts/open-webui/values-dev.yaml
```

### アンインストール

```bash
helm uninstall ollama
helm uninstall open-webui
```

## ArgoCD でのデプロイ

### 開発環境

```bash
# Ollama
kubectl apply -f k8s/argocd/apps/ollama-dev.yaml

# Open WebUI
kubectl apply -f k8s/argocd/apps/open-webui-dev.yaml
```

### 本番環境

```bash
# Ollama
kubectl apply -f k8s/argocd/apps/ollama-prd.yaml

# Open WebUI
kubectl apply -f k8s/argocd/apps/open-webui-prd.yaml
```

## 設定のカスチャート内の values ファイルで管理されています：

- **開発環境**: `values-dev.yaml`
  - NodePort サービス (ローカルアクセス用)
  - 小規模リソース設定
  - GPU サポート有効 (Ollama)

- **本番環境**: `values-prd.yaml`
  - ClusterIP サービス (Ingress 経由)
  - 大規模リソース設定
  - GPU サポート有効 (Ollama)サービス (Ingress 経由)
  - 大規模リソース設定
  - GPU サポート有効
  - レプリカ数増加 (Open WebUI)

## 注意事項

1. **GPU サポート**: Ollama は GPU を使用します。クラスタに NVIDIA GPU があることを確認してください。
2. **リポジトリ URL**: ArgoCD Application の `repoURL` を実際のリポジトリ URL に変更してください。
3. **永続化**: PVC を使用してデータを永続化しています。ストレージクラスが利用可能であることを確認してください。
