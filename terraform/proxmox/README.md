# Proxmox VM

TerraformはProxmox上のVMライフサイクルを管理します。Ubuntu内部とk3sの設定はAnsibleで管理します。

## 構成

```text
terraform/proxmox/
├── main.tf                  # VMごとの値とmodule呼び出し
├── providers.tf             # Proxmox接続設定
├── variables.tf             # Provider共通値のみ
├── outputs.tf
├── backend.tf.example       # S3 remote stateの例
└── modules/
    └── ubuntu-vm/           # Ubuntu VM共通設定
```

ルートの`main.tf`にはVMごとの差だけを記述します。UEFI、q35、VirtIO、ディスクオプションなどの共通設定は`modules/ubuntu-vm`にあります。

現在の`k3s-master01`は次の構成です。

- VM ID: `200`
- CPU: `6 vCPU`（1ソケット、6コア、CPU type `host`）
- メモリ: `24576 MiB`（24 GiB、バルーニングなし）
- OSディスク: `100 GiB`、`local-lvm`
- ISO: `local:iso/ubuntu-24.04.4-live-server-amd64.iso`
- ネットワーク: VirtIO、`vmbr0`
- 初期状態: 停止、自動起動なし、削除保護なし

## 認証

APIトークン認証を推奨します。認証情報は`.tf`や`.tfvars`に保存しません。

```bash
export PROXMOX_VE_API_TOKEN='terraform@pve!provider=replace-with-token-secret'
```

ユーザー名・パスワードで一時的に確認する場合は次の環境変数を使用します。

```bash
export PROXMOX_VE_USERNAME='root@pam'
read -s PROXMOX_VE_PASSWORD
export PROXMOX_VE_PASSWORD
```

## 実行

```bash
cd terraform/proxmox
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
terraform apply
```

## Ubuntuインストールのフェーズ

フェーズは`main.tf`の対象moduleで切り替えます。

1. 初回は`started = false`でVMを作成します。
2. `started = true`に変更してUbuntuインストーラーを起動します。
3. インストール完了後、`attach_install_iso = false`と`boot_from_iso = false`にします。
4. Ansibleで`qemu-guest-agent`をインストールして起動します。
5. `qemu_guest_agent_enabled = true`にします。
6. k3s移行後、`on_boot = true`と`protection = true`にします。

`qemu-guest-agent`がUbuntu内で稼働する前に有効化すると、Proxmoxが停止や再起動時に応答を待ち続ける可能性があります。

## VMの追加

数台であれば`main.tf`にmoduleブロックを追加します。VMごとにVM ID、名前、CPU、メモリなどを明示できるため、レビュー時に構成差が分かりやすくなります。同じ構成のVMを多数作る段階では、module呼び出しを`for_each`へ変更できます。

## Terraform state

現在はlocal backendです。最初の検証には利用できますが、恒久運用ではリポジトリやProxmoxホスト自身には保存せず、Proxmoxとは独立したremote backendを使用してください。

推奨例は、バージョニングを有効にしたAmazon S3とS3 lockfileです。`backend.tf.example`を`backend.tf`へコピーし、bucket名を設定してから移行します。

```bash
cp backend.tf.example backend.tf
terraform init -migrate-state
```

stateには機密情報が含まれる場合があります。bucketの暗号化、バージョニング、最小権限、公開アクセス禁止を設定してください。自宅内で完結させる場合は、Proxmoxとは別の物理NAS上のS3互換ストレージも候補ですが、使用する実装がstate lockingを正しくサポートすることを確認してください。
