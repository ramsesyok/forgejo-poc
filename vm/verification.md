# forgejo-lab 構築・検証結果

実施日: 2026-10-23～24（Asia/Tokyo）

## ホストと入力ファイル

| 項目 | 実測結果 |
|---|---|
| ホストOS | Windows 11 Home、64ビット、バージョン10.0.26300 |
| CPU / メモリ | 12論理CPU、物理メモリ約31.82 GiB |
| VMware Workstation | 26.0.0 build-25388281 |
| VMware CLI | `vmrun.exe`、`vmware-vdiskmanager.exe`、`mkisofs.exe`あり |
| Oracle Linux 8.10 DVD ISO | 指定パスに存在、14,156,824,576バイト |
| Cドライブ空き容量 | 作業開始時約89.51 GiB |
| NAT | VMnet8アダプター有効 |
| 既存VM | 作業開始時の`vmrun list`では稼働中0台。指定保存先に`forgejo-lab`は未存在 |

## 作成とインストール

- `New-ForgejoLab.ps1`で新規VM、100 GBの単一ファイル可変容量VMDK、Kickstart起動ISO、専用Ed25519 SSH鍵を作成した。仮想ディスク以外のホストディスクと既存VMは変更していない。
- 初回起動はVMware側の「No PCIe slot available for Ethernet0」で停止した。新規VMの仮想NICを`e1000e`から`e1000`へ変更し、再起動に成功した。この変更を作成スクリプトにも反映した。
- KickstartによりOracle Linux 8.10の最小構成を自動インストールし、再起動を確認した。インストーラ上の手動入力は行っていない。
- 当初生成したsudo用パスワードのハッシュには、PowerShellのパイプが付けたCRLFの`CR`が含まれていた。スクリプトをLFだけをOpenSSL標準入力に渡す方式へ修正し、既存の新規VMはレスキュー起動で`devops`のパスワードを再設定した。パスワード文字列とハッシュはこの文書に記録しない。
- インストール後は仮想CDを取り外し、一時的なローカルVNC診断設定とレスキューISOを削除した。通常の仮想ディスク起動後に再検証した。

## VM実測値

| 項目 | 結果 |
|---|---|
| VM保存先 | `C:\Users\ramse\Documents\Virtual Machines\forgejo-lab` |
| vCPU / メモリ | 4 vCPU / 8192 MiB（ゲスト表示約7.5 GiB） |
| 仮想ディスク | `sda` 100G。VMDK実ファイル約2.90 GB（可変容量） |
| OS | `Oracle Linux Server release 8.10` |
| カーネル | `5.15.0-206.153.7.1.el8uek.x86_64` |
| パーティション | `/boot` 1G、LVMの`/` 61.2G、swap 7.9G、`/home` 29.9G |
| ルートFS | `df -h /`で62G、使用2.6G、空き59G |
| NIC / DHCP | `enp0s17`、`192.168.131.131/24` |
| デフォルトゲートウェイ | `192.168.131.2` |

100 GBは仮想ディスクの上限値で、作業開始時のホスト空き容量約89.51 GiBを上回る。現在のVMDK実ファイルは約2.90 GBだが、ゲスト側で大量のデータを保存する前にホストの空き容量を確保する必要がある。

## SSH・保護設定の検証

- ホストから`ssh forgejo-lab`で`devops`として公開鍵接続に成功した。ホストのSSH設定は`HostName 192.168.131.131`、`User devops`、専用秘密鍵、`IdentitiesOnly yes`、`StrictHostKeyChecking yes`と確認した。今回の設定前に既存のSSH設定内容はなく、管理ブロックのみ追加された。
- 初回接続で保存した`known_hosts`のED25519ホスト鍵と、ゲストの公開ホスト鍵のフィンガープリントは共に`SHA256:yaoQLANd32L6sJpPbQPmqp87f/JUij1PtMJ2I+1Vxh8`。ホスト鍵照合は無効化していない。
- `openssh-server`、`open-vm-tools`、`firewalld`はインストール済み。`sshd`、`vmtoolsd`、`firewalld`、`NetworkManager`はすべて`enabled`かつ`active`。
- `getenforce`は`Enforcing`。`sshd -T`では`pubkeyauthentication yes`、`passwordauthentication no`、`permitrootlogin no`。
- firewalldは`running`。`enp0s17`は`public`ゾーンに属し、再起動後の許可サービスは`ssh`のみ。
- `devops`は`wheel`所属。`sudo -n true`は「a password is required」で失敗した。パスワードを入力した`sudo -l`は`(ALL) ALL`を表示し、実際に`firewall-cmd`の確認・設定を実行できた。`NOPASSWD: ALL`は設定していない。
- `vmrun getGuestIPAddress`は`vmtoolsd`が`active`でも「The VMware Tools are not running」と返した。ゲストIPはVMware NATのDHCPリースとゲスト側`ip -4 -brief address`で一致を確認した。

このOS準備段階の完了条件であるホストからのSSH接続確認は達成した。この記録時点ではForgejoとRunnerは未導入。その後の手動導入手順は[installation.md](../installation.md)、実施結果は[installation-verification.md](installation-verification.md)に記録した。

## スナップショット（2026-10-24）

- SSHでOS、SELinux、`sshd`・`vmtoolsd`・`firewalld`の稼働を確認した後、`forgejo-lab`だけを正常停止した。
- VMware Workstationの`vmrun snapshot`で、停止状態のスナップショット`OS準備完了`を作成した。`vmrun listSnapshots`は`Total snapshots: 1`と`OS準備完了`を表示した。
- VMを通常起動へ戻し、ホストから`ssh forgejo-lab`でOracle Linux 8.10、SELinux `Enforcing`、3サービスの稼働を再確認した。
- 実際にVMを再停止して`vmrun revertToSnapshot`で`OS準備完了`へ復元した。復元後に起動し、同じSSH接続・OS・SELinux・3サービス・DHCPアドレスを確認した。スナップショットは引き続き一覧に1件残っている。
