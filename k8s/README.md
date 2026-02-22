# Kubernetes リソース管理

このディレクトリには、クラスタで動作するすべてのリソース定義が含まれています。
ArgoCD の App of Apps パターンで GitOps を実現しています。

## ディレクトリ構成

```
k8s/
├── manifests/                        # クラスタ共通リソース
│   ├── namespaces/                  # Namespace定義
│   │   └── llm.yaml
│   ├── rbac/                        # ClusterRole等
│   │   └── clusterrole.yaml
│   ├── crds/                        # CRD (将来用)
│   └── storage/                     # StorageClass (将来用)
├── charts/                           # Helmチャート
│   ├── llm/                         # namespace単位で整理
│   │   ├── ollama/
│   │   │   ├── Chart.yaml
│   │   │   ├── values.yaml         # デフォルト設定
│   │   │   ├── values-dev.yaml     # 開発環境用設定
│   │   │   ├── values-prd.yaml     # 本番環境用設定
│   │   │   └── templates/
│   │   └── open-webui/
│   │       ├── Chart.yaml
│   │       ├── values.yaml
│   │       ├── values-dev.yaml
│   │       ├── values-prd.yaml
│   │       └── templates/
│   └── samba/
│       └── ...
└── argocd/
    ├── bootstrap/                    # App of Apps定義
    │   ├── app-of-apps-dev.yaml     # 開発環境のエントリーポイント
    │   └── app-of-apps-prd.yaml     # 本番環境のエントリーポイント
    └── applications/                 # 個別のApplication定義
        ├── base/                     # 環境共通
        │   └── manifests.yaml       # manifestsをArgoCDで管理
        ├── dev/                      # 開発環境
        │   └── llm/
        │       ├── ollama.yaml
        │       └── open-webui.yaml
        └── prd/                      # 本番環境
            └── llm/
                ├── ollama.yaml
                └── open-webui.yaml
```

## App of Apps パターン

App of Apps パターンは、ArgoCD Application リソース自体を管理する Application を作成する手法です。
1つの App of Apps で複数のアプリケーションを一元管理できます。

### デプロイフロー

```
app-of-apps-dev.yaml (bootstrap)
    ↓ 読み込む
applications/base/manifests.yaml → k8s/manifests/ (Namespace, RBAC等)
applications/dev/llm/ollama.yaml → k8s/charts/llm/ollama/
applications/dev/llm/open-webui.yaml → k8s/charts/llm/open-webui/
```

## デプロイ方法

### 開発環境（minikube）のデプロイ

```bash
# App of Apps をデプロイ（これだけで配下のすべてのリソースがデプロイされます）
kubectl apply -f k8s/argocd/bootstrap/app-of-apps-dev.yaml

# 状態確認
kubectl get applications -n argocd
kubectl get pods -n llm
```

デプロイされるもの：
1. Namespace `llm`
2. RBAC リソース
3. Ollama (GPU対応AIモデルランタイム)
4. Open WebUI (Web UI)

### 本番環境のデプロイ

```bash
kubectl apply -f k8s/argocd/bootstrap/app-of-apps-prd.yaml

# 状態確認
kubectl get applications -n argocd
kubectl get pods -n llm
```

## リソースの種類と配置場所

### manifests/ - クラスタ共通リソース
以下のような環境に依存しないリソースを配置：
- **CRD** (Custom Resource Definitions)
- **ClusterRole/ClusterRoleBinding**
- **Namespace定義**
- **StorageClass**
- **共通ConfigMap/Secret**

### charts/ - アプリケーション
以下のようなアプリケーション固有のリソースを配置：
- **Deployment, StatefulSet**
- **Service**
- **PVC**
- **環境ごとに設定が変わるリソース**

## 新しいアプリケーションの追加方法

### 1. Helm チャートを作成

```bash
# 新しいnamespace用のディレクトリを作成
mkdir -p k8s/charts/monitoring/prometheus

# Chart.yaml, values.yaml, templates/ を作成
# values-dev.yaml, values-prd.yaml で環境別設定
```

### 2. ArgoCD Application定義を作成

```bash
# 開発環境用
cat > k8s/argocd/applications/dev/monitoring/prometheus.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/obitwo/obitwo_house_cluster.git
    targetRevision: HEAD
    path: k8s/charts/monitoring/prometheus
    helm:
      valueFiles:
        - values-dev.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

# 本番環境用も同様に作成
```

### 3. App of Apps が自動的に検出

新しい Application 定義を Git にプッシュすると、App of Apps が自動的に検出してデプロイします。

## メリット

1. **一元管理**: 1つの App of Apps で複数のアプリケーションを管理
2. **環境分離**: dev と prd で完全に分離された管理
3. **GitOps**: すべての定義が Git リポジトリで管理され、変更履歴が追跡可能
4. **自動同期**: Git への変更が自動的にクラスタに反映
5. **スケーラビリティ**: namespace単位で整理され、拡張が容易

## トラブルシューティング

### App of Apps の状態確認

```bash
# App of Apps の状態
kubectl get app app-of-apps-dev -n argocd
kubectl describe app app-of-apps-dev -n argocd

# 配下のすべての Application の状態
kubectl get app -n argocd
```

### 個別アプリケーションの状態確認

```bash
# Ollama の状態
kubectl get app ollama-dev -n argocd
kubectl logs -n llm -l app.kubernetes.io/name=ollama

# Open WebUI の状態
kubectl get app open-webui-dev -n argocd
kubectl logs -n llm -l app.kubernetes.io/name=open-webui
```

### 手動同期

```bash
# ArgoCD CLI を使用
argocd app sync app-of-apps-dev
argocd app sync ollama-dev
argocd app sync open-webui-dev

# または kubectl を使用
kubectl patch app ollama-dev -n argocd -p '{"operation":{"sync":{}}}' --type merge
```

### 削除

```bash
# 開発環境のすべてのアプリを削除
kubectl delete -f k8s/argocd/bootstrap/app-of-apps-dev.yaml

# 本番環境のすべてのアプリを削除
kubectl delete -f k8s/argocd/bootstrap/app-of-apps-prd.yaml

# 特定のアプリのみ削除
kubectl delete app ollama-dev -n argocd
```

## ローカル開発

### Helm テンプレートの検証

```bash
# テンプレートの生成を確認
helm template ollama ./k8s/charts/llm/ollama -f ./k8s/charts/llm/ollama/values-dev.yaml

# dry-run でインストールテスト
helm install ollama ./k8s/charts/llm/ollama -f ./k8s/charts/llm/ollama/values-dev.yaml --dry-run
```

### ArgoCD UI でのアクセス

```bash
# ArgoCD UIにアクセス
kubectl port-forward svc/argocd-server -n argocd 8080:443

# ブラウザで https://localhost:8080 にアクセス
# 初期パスワードを取得
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## ArgoCD 初回セットアップ手順

### 前提条件

- minikubeが起動していること
- kubectlが設定済みであること
- gitクローンが完了していること

### セットアップ

#### 1. ArgoCD Namespace の作成と ArgoCD のインストール

```bash
# ArgoCD namespace を作成
kubectl create namespace argocd

# 公式 ArgoCD Manifest をインストール
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

ArgoCD のデプロイメントが起動するまで待ちます：

```bash
# ステータスを確認
kubectl get pods -n argocd -w
# すべてのポッドが Running になるまで待機
```

#### 2. クラスタ共通リソース (Namespace, RBAC等) の作成

```bash
# llm namespace と ClusterRole を作成
kubectl apply -f k8s/manifests/namespaces/llm.yaml
kubectl apply -f k8s/manifests/rbac/clusterrole.yaml
```

#### 3. App of Apps パターンの初期化

```bash
# 共通リソースを管理する Application を作成
kubectl apply -f k8s/argocd/applications/base/manifests.yaml

# 開発環境の App of Apps をデプロイ
kubectl apply -f k8s/argocd/bootstrap/app-of-apps-dev.yaml
```

#### 4. 同期状態の確認

```bash
# Application の状態を確認
kubectl get applications -n argocd

# 詳細な情報を確認
kubectl describe app app-of-apps-dev -n argocd

# 子アプリケーションの状態を確認
kubectl get applications -n argocd -o wide
```

期待される出力（初回は同期に数分かかる可能性があります）：

```
NAME                SYNC STATUS     HEALTH STATUS
cluster-manifests   Synced          Healthy
app-of-apps-dev     Synced          Healthy
ollama-dev          Synced          Healthy
open-webui-dev      Synced          Healthy
```

#### 5. リソースのデプロイ確認

```bash
# llm namespace にデプロイされたポッドを確認
kubectl get pods -n llm

# サービスを確認
kubectl get svc -n llm

# デプロイメントを確認
kubectl get deployment -n llm
```

期待される出力（起動に数分かかる場合があります）：

```
NAME                                 READY   STATUS    RESTARTS
ollama-6f8c9d7-abcde                 1/1     Running   0
open-webui-6g8d9e7-bcdef             1/1     Running   0
```

### ArgoCD UI へのアクセス

#### ポートフォワードの設定

```bash
# ArgoCD UI にアクセスできるようにポートフォワード
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

#### UI へのアクセス

- ブラウザで `https://localhost:8080` にアクセス
- ユーザー名: `admin`
- パスワード: 下記コマンドで取得

```bash
# 初期パスワードを取得
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo  # 改行を追加
```

#### パスワード変更の推奨

セキュリティのため、初回ログイン後にパスワードを変更してください：

1. UI の右上のユーザーアイコンをクリック
2. "User Info" をクリック
3. "Update Password" で新しいパスワードを設定

または CLI から：

```bash
# CLI でパスワードを変更
argocd account update-password \
  --account admin \
  --current-password <現在のパスワード> \
  --new-password <新しいパスワード> \
  --server localhost:8080 \
  --insecure
```

### 本番環境のセットアップ

```bash
# 本番環境の App of Apps をデプロイ
kubectl apply -f k8s/argocd/bootstrap/app-of-apps-prd.yaml

# 本番環境のアプリケーション状態を確認
kubectl get applications -n argocd -l env=prd
```

### トラブルシューティング

#### Application の同期が失敗している場合

```bash
# 詳細なエラーメッセージを確認
kubectl describe app <アプリケーション名> -n argocd | grep -A 10 "Message:"

# ArgoCD のログを確認
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller -f

# リソースを強制的に削除してリセット
kubectl delete app <アプリケーション名> -n argocd
```

#### ポッドが起動しない場合

```bash
# ポッドのログを確認
kubectl logs -n llm <ポッド名>

# ポッドの詳細情報を確認
kubectl describe pod -n llm <ポッド名>

# Events を確認
kubectl get events -n llm --sort-by='.lastTimestamp'
```

### 参考情報

- ArgoCD Documentation: https://argo-cd.readthedocs.io/
- 本リポジトリのディレクトリ構成については上記「ディレクトリ構成」セクションを参照
- App of Apps パターンについては `argocd/bootstrap/app-of-apps-dev.yaml` のコメントを参照

## 参考リンク

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Helm Documentation](https://helm.sh/docs/)
- [App of Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
