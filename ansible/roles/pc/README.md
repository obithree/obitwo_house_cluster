# PC Role

Ubuntu PCにデスクトップアプリケーションをインストールするAnsible roleです。

## インストールされるソフトウェア

### デスクトップアプリケーション
- **Google Chrome**: Webブラウザ
- **Steam**: ゲームプラットフォーム
- **Discord**: チャット・コミュニケーションツール
- **VSCode**: コードエディタ

### ドライバー
- **NVIDIA Driver**: NVIDIAグラフィックボードドライバー (自動検出・インストール)

### 開発ツール（オプション: `install_dev_tools: true` で有効化）
開発ツールは `tasks/dev-tools.yml` に分離されており、必要に応じてインストールできます。

#### Docker
- **Docker CE**: コンテナプラットフォーム
- **Docker Compose**: マルチコンテナアプリケーション管理（plugin版 + standalone版）

#### CLI ツール
- `vim` - テキストエディタ
- `git` - バージョン管理システム
- `htop` - システムモニター
- `tmux` - ターミナルマルチプレクサ
- `build-essential` - コンパイラ・開発ツール
- `net-tools` - ネットワークツール
- `tree` - ディレクトリ構造表示
- `jq` - JSON処理
- `unzip` / `zip` - 圧縮・展開ツール
- `ncdu` - ディスク使用量解析
- `rsync` - ファイル同期

## 必要な権限

このroleは `sudo` 権限が必要です。Playbookで `become: yes` を指定してください。

## 使用方法

### Playbookの例

```yaml
---
- name: Ubuntu PCのセットアップ
  hosts: pc
  become: yes
  roles:
    - common
    - role: pc
      vars:
        install_dev_tools: true  # 開発ツールをインストールする
```

開発ツールが不要な場合:

```yaml
---
- name: Ubuntu PCのセットアップ
  hosts: pc
  become: yes
  roles:
    - common
    - pc  # install_dev_tools: false がデフォルト
```

### 実行コマンド

```bash
ansible-playbook -i inventory/pc/hosts.yml playbook/pc-setup.yml --ask-become-pass
```

## 変数

デフォルトの変数は `defaults/main.yml` で定義されています。

### 主要な変数

- `install_dev_tools`: 開発ツール（CLI Tools, Docker, Docker Compose）をインストールするか（デフォルト: `false`）
- `install_nvidia_driver`: NVIDIAドライバーをインストールするか（デフォルト: `true`）

## ファイル構成

- `tasks/main.yml`: メインタスク（デスクトップアプリ、NVIDIAドライバー）
- `tasks/dev-tools.yml`: 開発ツール関連タスク（CLI Tools, Docker）
- `defaults/main.yml`: デフォルト変数

## 注意事項

- Steamのインストールには32bitアーキテクチャの有効化が必要です
- Discordは公式サイトから最新版をダウンロードしてインストールします
- インターネット接続が必要です
- **NVIDIAドライバーをインストールした後は、システムの再起動が必要です**
- NVIDIAドライバーは `ubuntu-drivers autoinstall` を使用して、システムに最適なドライバーを自動的にインストールします

### 開発ツールをインストールする場合の注意事項
- **Dockerを使用するには、ログアウト・ログイン（または再起動）が必要です**（dockerグループへの追加を反映するため）
- Docker Composeは2つの方法でインストールされます:
  - `docker compose` (plugin版 - 推奨)
  - `docker-compose` (standalone版 - 互換性のため)

