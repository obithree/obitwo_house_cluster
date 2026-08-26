# Ubuntu VM module

Proxmox上にUbuntu Server VMを作成するための、このリポジトリ内専用moduleです。

VMごとに変わるVM ID、名前、CPU、メモリ、ディスク容量、起動状態を入力として受け取り、次の共通設定を適用します。

- q35、OVMF/UEFI
- VirtIO SCSI single
- raw形式のEFI・OSディスク
- discard、I/O thread、SSD emulation
- VirtIOネットワーク
- Linux guest設定
- 安全側の削除・停止設定

Ubuntu内部のユーザー、ネットワーク、パッケージ、k3sはこのmoduleの対象外で、Ansibleが担当します。
