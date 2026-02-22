# Kubernetes Manifests

このディレクトリには、クラスタ全体に関わる共通リソースを管理します。

## ディレクトリ構成

```
manifests/
├── namespaces/          # Namespace定義
│   └── llm.yaml        # LLMアプリケーション用namespace
├── rbac/                # RBAC (ClusterRole, ClusterRoleBinding)
│   └── clusterrole.yaml
├── crds/                # Custom Resource Definitions
└── storage/             # StorageClass等
```

## 使い方

### Namespace作成

```bash
kubectl apply -f k8s/manifests/namespaces/
```

### RBAC設定

```bash
kubectl apply -f k8s/manifests/rbac/
```

### 全ての共通リソースを適用

```bash
kubectl apply -R -f k8s/manifests/
```

## manifestsとchartsの使い分け

### manifestsに入れるべきもの
- CRD (Custom Resource Definitions)
- ClusterRole/ClusterRoleBinding
- Namespace定義
- StorageClass
- 環境によって変わらない共通ConfigMap/Secret

### chartsに入れるべきもの
- アプリケーション固有のリソース (Deployment, Service等)
- 環境ごとに設定が変わるもの
- Helmで管理したいもの

## ArgoCD連携

共通リソースもArgoCDで管理する場合は、`k8s/argocd/applications/base/`にApplication定義を作成できます：

```yaml
# k8s/argocd/applications/base/manifests.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-manifests
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/obitwo/obitwo_house_cluster.git
    targetRevision: HEAD
    path: k8s/manifests
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```
