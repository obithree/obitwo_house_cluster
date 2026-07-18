# obitwo_house_cluster

自宅の Raspberry Pi クラスター (k3s) および PC のインフラストラクチャを管理するリポジトリ。

## アーキテクチャ

```
  obitwo-pc (Ubuntu, k3s agent, NVIDIA GPU)
            |
  raspi01   -- (k3s server + worker)
  raspi02   -- (k3s worker)
  raspi03   -- (k3s worker)
  raspi04   -- (k3s worker)
```

- **raspi01**: Raspberry Pi 4 / k3s マスターノード兼ワーカー
- **raspi02 - raspi04**: Raspberry Pi 4 / k3s ワークノード
- **obitwo-pc**: Ubuntu PC / k3s エージェント + NVIDIA GPU

## ディレクトリ構成

```
.
├── ansible/          # サーバー初期設定用 Ansible Playbook
│   ├── inventory/    # ホスト一覧 (hosts.yml)
│   ├── playbook/     # 実行用プレイブック集
│   └── roles/        # カスタムロール群
│       ├── common/   # コモンセットアップ
│       ├── k3s/      # k3s のインストール・設定
│       ├── pc/       # PC 環境構築 (CUDA, Docker など)
│       ├── minikube/ # ローカル用 Minikube
│       ├── ollama/   # Ollama インストール
│       └── ...
├── k8s/              # Kubernetes リソース管理
│   ├── Makefile      # ビルドヘルパー
│   ├── argocd/       # ArgoCD アプリケーション定義
│   │   ├── bootstrap/  # App of Apps (dev/prd)
│   │   └── applications/ # ネームスペース毎の AppSet
│   └── charts/       # カスタム Helm Charts
│       ├── argocd/       # ArgoCD (base)
│       ├── common/       # 共通インフラ (Longhorn, MetalLB, Tailscale)
│       ├── llm/          # LLM サービス (Ollama, Open WebUI, LiteLLM, SearXNG)
│       ├── image-gen/    # Stable Diffusion WebUI
│       ├── monitoring/   # Monitoring stack (Prometheus, Grafana, Loki, Alloy)
│       ├── pihole/       # DNS / Ad-blocker
│       └── samba/        # SMB ストレージ共有
├── scripts/          # 便利スクリプト
│   └── ollama-benchmark.py  # Ollama パフォーマンスベンチマーク
└── docs/             # ドキュメント
    ├── 20260530_longhorn-setup/
    ├── 20260606_grafana-pod-events/
    └── 20260620_ollama-performance-investigation/
```

## Kubernetes サービス一覧

| カテゴリ     | サービス             | 概要                                      |
|-------------|---------------------|------------------------------------------|
| **LLM**     | Ollama              | ローカル LLM 推論エンジン                 │
|             | Open WebUI          | Ollama 用フロントエンド (OpenAI互換 UI)    │
|             | LiteLLM             | OpenAI 互換 API ゲートウェイ              │
|             | SearXNG             | プライバシー重視のメタエンジン            │
| **インフラ** | MetalLB           | ロードバランサー型 IP プロバイダ           │
|             | Longhorn          | ディスク型ブロックストレージ                │
|             | Tailscale         | メッシュ VPN                               │
| **モニタリング** | Prometheus    | メetrics収集・アラート                     │
|             | Grafana           | ダッシュボード (監視用)                    │
|             | Loki              | ログ集約                                 │
|             | Alloy             | 分散トラース・メトリクスエクスポート        │
| **その他**  | Pi-hole          | DNS / Ad-blocker                          │
|             | Samba             | SMB ファイル共有                            │
| **画像生成** | Stable Diffusion WebUI | GPU加速のイメージジェネレーター         │

## 環境区分

- **dev**: 開発環境 (ArgoCD `applications/dev/`)
- **prd**: 本番環境 (ArgoCD `applications/prd/`)

各環境とも Helm Values (`values-dev.yaml`, `values-prd.yaml`) で差分管理している。

## 初期セットアップ

Ansible でサーバーの初始化を行う。

```bash
# ホスト情報を inventory/inventory.yml に設定後、実行する
ansible-playbook -i inventory/hosts.yml playbook/raspi-master.yml    # マスターノード
ansible-playbook -i inventory/hosts.yml playbook/raspi-setup.yml     # ワーカーノード
ansible-playbook -i inventory/hosts.yml playbook/pc-setup.yml         # PC (obitwo-pc)
```

## Kubernetes デプロイメント

ArgoCD の App of Apps パターンで構成を管理している。

```bash
# k8s 配下で実行
cd k8s && make help          # ターゲットの一覧表示
```

## メンテナンスドロール一覧

| ロール           | 内容                                   │
|-----------------|---------------------------------------│
| `common`        | OS ユーザー, apt, タイムゾーンなど共通設定 │
| `k3s`           | k3s サーバー/エージェントのインストール    │
| `pc`            | Ubuntu PC 用開発環境 (CUDA, Docker, ... ) │
| `minikube`      | ローカル用 Minikube                    │
| `ollama`        | Ollama のインストールと設定              │
| `ai303-bluetooth` | AI Speaker 303 Bluetooth 接続          │
| `hifidac`       | HiFiDAC デバイス設定                      │

## ドキュメント

過去のセットアップ調査やインシデントの記録を `docs/` に日付付きディレクトリで保存している。

