# Steam Link role

Ubuntu の GDM ログインを Wayland から Xorg に切り替え、Steam Remote Play / Steam Link のホストとして使うためのロールです。

実施内容:

- `xserver-xorg`、`x11-xserver-utils`、`dbus-x11` を導入
- `/etc/gdm3/custom.conf` に `WaylandEnable=false` と `DefaultSession=ubuntu-xorg.desktop` を設定
- 対象ユーザーの AccountsService の既存属性を維持し、`XSession=ubuntu-xorg` を設定
- i386 アーキテクチャと multiverse を有効化して `steam-installer` をAPTで導入
- GDM を有効化して起動

## 使用例

`playbook/steamlink-setup.yml` は `pc` グループを対象にします。

```bash
cd ansible
ansible-playbook playbook/steamlink-setup.yml --limit obitwo-pc --ask-become-pass
```

既定では GUI セッションを強制終了しないため、実行後にログアウト・ログインまたは再起動してください。直ちに反映する場合は `-e steamlink_restart_gdm=true` を指定できます。この指定は実行中の GUI セッションを終了します。

## 主な変数

- `steamlink_user`: Xorg セッションを使うユーザー（既定: `ansible_user`）
- `steamlink_restart_gdm`: 変更後に GDM を再起動するか（既定: `false`）
- `steamlink_set_user_xsession`: ユーザーのセッションを Xorg に固定するか（既定: `true`）
- `steamlink_install_steam`: APT版 `steam-installer` を導入するか（既定: `true`）

このロールはSteam Installerの導入までを行います。Steamの初回起動、アカウント認証、Steam Guard、Remote Playの確認とSteam Link端末とのペアリングは、X11セッションへログイン後に手動で実施してください。
