# Minikube Role

Ubuntu PCにMinikubeをインストール・セットアップするAnsible roleです。

## 概要

Minikubeは、ローカル環境でKubernetesクラスターを簡単に実行できるツールです。
このroleは以下をセットアップします：

- kubectl（Kubernetesコマンドラインツール）
- Minikube本体
- Minikubeクラスターの起動
- 便利なアドオンの有効化

## 前提条件

- Docker がインストールされていること（`minikube_driver: docker` の場合）
- インターネット接続が必要

## インストールされるコンポーネント

- **kubectl**: Kubernetes CLI
- **Minikube**: ローカルKubernetesクラスター

## デフォルトのアドオン

- `ingress`: Ingress コントローラー
- `dashboard`: Kubernetes ダッシュボード
- `metrics-server`: メトリクス収集

## 使用方法

### Playbookの例

```yaml
---
- name: Minikube のセットアップ
  hosts: localhost
  roles:
    - role: minikube
      vars:
        minikube_driver: docker
        minikube_cpus: 4
        minikube_memory: "8192mb"
        minikube_addons:
          - ingress
          - dashboard
          - metrics-server
          - registry
```

### 最小構成の例

```yaml
---
- name: Minikube のセットアップ（デフォルト設定）
  hosts: localhost
  roles:
    - minikube
```

## 変数

以下の変数を `defaults/main.yml` で設定できます：

| 変数名 | デフォルト値 | 説明 |
|--------|-------------|------|
| `minikube_version` | `latest` | Minikubeのバージョン |
| `minikube_driver` | `docker` | 使用するドライバー（docker, kvm2, virtualbox等） |
| `minikube_cpus` | `2` | 割り当てるCPU数 |
| `minikube_memory` | `4096mb` | 割り当てるメモリ容量 |
| `minikube_disk_size` | `20g` | ディスクサイズ |
| `kubernetes_version` | `stable` | Kubernetesのバージョン |
| `minikube_addons` | `[ingress, dashboard, metrics-server]` | 有効化するアドオン |
| `minikube_autostart` | `false` | システム起動時の自動起動 |

## 利用可能なドライバー

- `docker`: Docker コンテナ（推奨）
- `kvm2`: KVM仮想化
- `virtualbox`: VirtualBox
- `none`: ベアメタル実行

## Playbook実行コマンド

```bash
ansible-playbook -i inventory/pc/hosts.yml playbook/minikube-setup.yml --ask-become-pass
```

## セットアップ後の確認コマンド

```bash
# クラスターの状態確認
minikube status

# ノードの確認
kubectl get nodes

# ダッシュボードの起動
minikube dashboard

# アドオン一覧
minikube addons list

# クラスター情報
kubectl cluster-info
```

## よく使うコマンド

```bash
# クラスターの起動
minikube start

# クラスターの停止
minikube stop

# クラスターの削除
minikube delete

# SSH接続
minikube ssh

# サービスへのアクセス
minikube service <service-name>

# IPアドレスの取得
minikube ip
```

## トラブルシューティング

### Docker が見つからない

```bash
# Dockerのインストール状態を確認
docker --version

# Docker サービスの状態確認
sudo systemctl status docker
```

### クラスターが起動しない

```bash
# ログの確認
minikube logs

# クラスターの削除と再作成
minikube delete
minikube start
```

### メモリ不足エラー

変数 `minikube_memory` の値を増やしてください：

```yaml
minikube_memory: "8192mb"  # 8GB
```

## 注意事項

- Dockerドライバーを使用する場合、事前にDockerのインストールが必要です
- 初回起動時はKubernetesイメージのダウンロードに時間がかかります
- ホストマシンに十分なリソース（CPU、メモリ）があることを確認してください
- `minikube_autostart: true` を設定すると、システム起動時に自動的にクラスターが起動します

## ファイル構成

- `tasks/main.yml`: メインタスク（kubectl、Minikubeのインストールとセットアップ）
- `defaults/main.yml`: デフォルト変数
- `templates/minikube.service.j2`: systemd サービスファイルテンプレート（自動起動用）
