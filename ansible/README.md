# Raspberry Pi 4 初期設定用 Ansible Playbook

このプロジェクトは、Raspberry Pi 4 に基本的な初期設定を行うための Ansible Playbook です。

## 使用方法

1. `inventory/inventory.ini` に Raspberry Pi 4 のホスト情報を設定してください。
2. `group_vars/all.yml` に `sudo_password` を設定してください（SSH キー認証を使用する場合は不要）。
3. 以下のコマンドで Playbook を実行します。

```bash
ansible-playbook -i inventory/inventory.ini playbook/site.yml
