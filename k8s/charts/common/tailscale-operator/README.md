# Tailscale Kubernetes Operator

k3sクラスターへのリモートアクセスをTailscaleで提供するOperatorです。  
IngressリソースをTailscaleのMagicDNSに自動的に公開します。

## アーキテクチャ

```
Tailscaleクライアント（PC/スマホ）
    ↓ MagicDNS (*.tailnet.ts.net)
Tailscale Operator (tailscaleネームスペース)
    ↓ Ingress
Traefikなど各サービス
```

## 初回セットアップ

### 1. Tailscale Admin ConsoleでOAuthクライアントを作成

https://login.tailscale.com/admin/settings/oauth

- Scope: `Devices` → `Write`を選択
- Tag: `tag:k8s-operator`を指定

### 2. ACLにタグを追加

Tailscale Admin Console → Access Controlsで以下を追加：

```json
"tagOwners": {
  "tag:k8s-operator": ["autogroup:admin"]
}
```

### 3. Secretに認証情報を設定

ArgoCDがデプロイした空のSecretに、取得した認証情報を書き込む：

```bash
kubectl patch secret operator-oauth -n tailscale \
  --type='json' \
  -p='[
    {"op":"replace","path":"/data/client_id","value":"'$(echo -n "<CLIENT_ID>" | base64)'"},
    {"op":"replace","path":"/data/client_secret","value":"'$(echo -n "<CLIENT_SECRET>" | base64)'"}
  ]'
```

> Secretの`data`フィールドはArgoCD Application側で`ignoreDifferences`に設定されているため、ArgoCDの`selfHeal`で上書きされない。

### 4. Operatorを再起動

Secretを書き込んだ後、Operatorが認証情報を読み込むよう再起動する：

```bash
kubectl rollout restart deployment -n tailscale
```

## アクセスURL

Tailscale接続後、以下のURLでサービスにアクセス可能：

| サービス | URL |
|---|---|
| ArgoCD | `https://argocd.<tailnet>.ts.net` |
| open-webui | `https://open-webui.<tailnet>.ts.net` |
| pihole | `https://pihole.<tailnet>.ts.net` |

`<tailnet>`はTailscale Admin Consoleで確認できるネットワーク名。

## 関連ファイル

- `Chart.yaml` - Helmチャート定義（tailscale-operator v1.96.5）
- `values-prd.yaml` - 本番環境の設定値
- `templates/secret.yaml` - OAuth認証情報を格納するSecretの初期テンプレート
- `../../argocd/applications/prd/common/tailscale-operator.yaml` - ArgoCD Application定義
