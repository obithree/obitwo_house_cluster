# Steam Link role

Ubuntu の GDM ログインをWaylandからXorgへ切り替え、Steam Remote Play / Steam Linkのホストとして使うためのロールです。Ubuntu 25.10以降ではGNOMEのXorgセッションが提供されないため、XfceのX11セッションを導入します。Ubuntu 24.04以前では従来のUbuntu Xorgセッションを使用します。

実施内容:

- `xserver-xorg`、`x11-xserver-utils`、`dbus-x11` を導入
- Ubuntu 25.10以降では`xfce4`を導入し、`xfce.desktop`をX11セッションとして使用
- `/etc/gdm3/custom.conf` に `WaylandEnable=false` と対象の`DefaultSession`を設定
- 対象ユーザーのAccountsServiceの既存属性を維持し、`Session`、`SessionType=x11`、互換用の`XSession`を設定
- i386 アーキテクチャと multiverse を有効化して `steam-installer` をAPTで導入
- X11ログイン時に`steam -cef-disable-gpu -bigpicture`を自動起動
- GDM を有効化して起動

## 使用例

`playbook/steamlink-setup.yml` は `steamlink` グループを対象にします。既定の対象は`steam.obitwo.arpa`（`192.168.100.129`）です。

```bash
cd ansible
ansible-playbook playbook/steamlink-setup.yml --limit steam.obitwo.arpa --ask-become-pass
```

既定では GUI セッションを強制終了しないため、実行後にログアウト・ログインまたは再起動してください。直ちに反映する場合は `-e steamlink_restart_gdm=true` を指定できます。この指定は実行中の GUI セッションを終了します。

## 主な変数

- `steamlink_user`: Xorg セッションを使うユーザー（既定: `ansible_user`）
- `steamlink_session_type`: AccountsServiceへ設定するセッション種別（既定: `x11`）
- `steamlink_restart_gdm`: 変更後に GDM を再起動するか（既定: `false`）
- `steamlink_set_user_xsession`: ユーザーのセッションを Xorg に固定するか（既定: `true`）
- `steamlink_install_steam`: APT版 `steam-installer` を導入するか（既定: `true`）
- `steamlink_autostart_big_picture`: ログイン時にSteam Big Pictureを自動起動するか（既定: `true`）
- `steamlink_disable_steam_cef_gpu`: Big PictureのCEF GPU描画を無効化するか（既定: `true`）。ゲーム描画とVAAPI/NVENCエンコードには影響しません
- `steamlink_configure_primary_gpu`: パススルーGPUをXorgのプライマリに設定するか（既定: `true`）
- `steamlink_primary_gpu_driver`: プライマリにするXorgドライバー（既定: `amdgpu`）

このロールはSteam Installerの導入とBig Pictureの自動起動設定までを行います。Steamの初回起動、アカウント認証、Steam Guard、Remote Playの確認とSteam Link端末とのペアリングは、X11セッションへログイン後に手動で実施してください。

GPUパススルー環境では、既定で `amdgpu` をXorgのプライマリGPUに設定します。AMD GPUへモニターまたはダミープラグを接続してから実行してください。Proxmoxの仮想ディスプレイを無効にすると、noVNCコンソールは利用できなくなるため、事前にSSH接続を確認してください。
