# forgejo-lab: Oracle Linux 8.10 検証VM

## 目的と範囲

Windows上のVMware Workstationに、Oracle Linux 8.10のGUIなしVMをKickstartで作成し、ホストからSSH公開鍵で接続する。この文書はOS準備までを扱う。続くForgejoとRunnerの手動導入手順と再導入結果は[installation.md](../installation.md)に記録した。
CodexはWindowsホスト側だけで実行し、VM内には導入しない。

## 構成

| 項目 | 設定 |
|---|---|
| VM名 | `forgejo-lab` |
| 保存先 | `C:\Users\ramse\Documents\Virtual Machines\forgejo-lab` |
| CPU / メモリ | 4 vCPU / 8192 MiB |
| ディスク | 100 GB、単一ファイルの可変容量VMDK |
| ネットワーク | VMware NAT（VMnet8）、ゲストはDHCP |
| インストールISO | `C:\Users\ramse\Downloads\OracleLinux-R8-U10-x86_64-dvd.iso` |
| ファームウェア | BIOS |
| ユーザー | `devops`（wheel、sudoにはパスワードが必要） |
| SSH | Ed25519公開鍵認証、パスワードログイン無効 |
| 保護 | SELinux enforcing、firewalld有効、SSHサービスのみ許可 |

このVMのNAT接続は外向き通信が可能で、エアギャップ構成ではない。ForgejoとRunnerの外部参照を避ける設定は、[installation.mdのオフライン設定](../installation.md#8-forgejoとrunnerのオフライン設定)を参照する。

## ファイルと秘密情報

- [New-ForgejoLab.ps1](New-ForgejoLab.ps1) が空の新規VMフォルダを作成する。既存ファイルがあるフォルダには上書きしない。
- [forgejo-lab.ks.in](forgejo-lab.ks.in) は秘密情報のないKickstartテンプレート。パーティション作成対象を新規VM内の`sda`に限定している。
- 生成したEd25519秘密鍵: `C:\Users\ramse\.ssh\forgejo-lab_ed25519`。公開鍵は同じ名前に`.pub`を付けたファイル。
- `devops`のコンソールおよびsudo用パスワード: `C:\Users\ramse\.ssh\forgejo-lab-console-password.txt`。生成時に当該ユーザーだけが読めるACLを設定する。
- `.work`はGit管理対象外。生成Kickstartにはパスワードのハッシュと公開鍵だけを含む。起動ISOはVMフォルダに置く。いずれもGitに追加しない。

## 作成手順

PowerShellでリポジトリに移動して実行する。VMware CLI、Git同梱OpenSSL、VM保存先へのアクセス権が必要。VMwareの実行権限が不足する場合は管理者としてPowerShellを起動する。

```powershell
Set-Location C:\Users\ramse\Projects\forgejo-poc
.\vm\New-ForgejoLab.ps1
& 'C:\Program Files\VMware\VMware Workstation\vmrun.exe' -T ws start 'C:\Users\ramse\Documents\Virtual Machines\forgejo-lab\forgejo-lab.vmx' nogui
```

スクリプトは元のDVD ISOから起動カーネルとinitrdを取り出し、Kickstart入りの小さな起動ISOを作る。VMにはこの起動ISOと元のDVD ISOを別々の仮想CDとして接続する。起動ISOの既定ブートエントリに`inst.ks=cdrom:/ks.cfg`とDVDのラベルを指定しており、インストーラ画面での入力は不要。VMware同梱`mkisofs.exe`はVMwareインストールフォルダで実行する。

Kickstartは`sda`だけを対象に`ignoredisk`、`clearpart`、`autopart --type=lvm`を使う。新規VMにはこの仮想ディスク1台だけを接続する。既存VMや既存ディスクを対象にしない。

## SSH接続の設定と検証

インストールが再起動まで完了したら、VMware NATのDHCPリースから`forgejo-lab`の最新エントリを探し、ゲストIPを確認する。VMwareコンソールで`ip -4 -brief address`を実行しても確認できる。この環境では`vmrun getGuestIPAddress`は`vmtoolsd`が稼働中でもエラーになったため、検証済みの方法はDHCPリースとゲスト側のIP表示である。

```powershell
Get-Content 'C:\ProgramData\VMware\vmnetdhcp.leases' |
    Select-String 'client-hostname "forgejo-lab"' -Context 4,0
```

初回SSHは`StrictHostKeyChecking=accept-new`でホスト鍵を`known_hosts`に記録し、その後は厳密な照合を使う。初回のホスト鍵の真正性をより強く確認する場合は、VMwareコンソールで`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`を実行し、ホスト側の提示フィンガープリントと照合する。

```powershell
$ip = '<vmrunで取得したIPv4アドレス>'
ssh -o StrictHostKeyChecking=accept-new -o PasswordAuthentication=no -i "$env:USERPROFILE\.ssh\forgejo-lab_ed25519" "devops@$ip" 'cat /etc/oracle-release'
.\vm\Set-ForgejoLabSshConfig.ps1 -HostAddress $ip
ssh forgejo-lab 'cat /etc/oracle-release; ip -4 -brief address; lsblk; df -h /; getenforce; systemctl is-active sshd vmtoolsd firewalld'
```

`Set-ForgejoLabSshConfig.ps1`は既存の`~/.ssh/config`の内容を保持し、管理対象ブロックだけを追加・更新する。既存ファイルがあればバックアップを作る。DHCPでIPが変わった場合は、新しいIPで同スクリプトを再実行する。`StrictHostKeyChecking yes`を設定し、鍵照合を無効化しない。

`devops`はwheel所属で、sudo時にユーザーパスワードが必要。`sudo -n true`はパスワード要求で失敗し、パスワードを入力した`sudo -l`は`(ALL) ALL`を表示する。管理者操作はパッケージ導入、サービス管理、ファイアウォール設定、Forgejo用ファイル配置に限って使用する予定。無条件の`NOPASSWD: ALL`は設定しない。今後より狭い運用権限が必要になれば、Forgejo導入時に具体的なコマンドを決めて別途sudoersを設計する。

## 参照資料

- [Oracle Linux 8 Kickstartインストール](https://docs.oracle.com/en/operating-systems/oracle-linux/8/install/install-StartingtheKickstartInstallation.html)
- [Oracle Linux 8 Kickstart設定例](https://docs.oracle.com/en/operating-systems/oracle-linux/8/install/install-AbouttheKickstartConfigurationFile.html)
- [VMware Workstation Proユーザーガイド](https://techdocs2-prod.adobecqms.net/content/dam/broadcom/techdocs/us/en/pdf/vmware/desktop-hypervisors/workstation/vmware-workstation-pro-17-0.pdf)

## 実施結果

実測値は[検証結果](verification.md)に記録する。

## OS準備完了スナップショットへの復元

`OS準備完了`はOS準備とSSH検証の完了後、VMを正常停止した状態で作成した。復元するとスナップショット作成後にVMへ加えた変更は失われる。復元するときは対象VMだけを停止してから実行する。

```powershell
$vmx = 'C:\Users\ramse\Documents\Virtual Machines\forgejo-lab\forgejo-lab.vmx'
$vmrun = 'C:\Program Files\VMware\VMware Workstation\vmrun.exe'
& $vmrun -T ws stop $vmx soft
& $vmrun -T ws revertToSnapshot $vmx 'OS準備完了'
& $vmrun -T ws start $vmx nogui
ssh forgejo-lab 'cat /etc/oracle-release'
```

復元前にスナップショット名を確認する場合は`& $vmrun -T ws listSnapshots $vmx`を実行する。DHCPアドレスが変わった場合は、SSHの`HostName`を[接続設定手順](#ssh接続の設定と検証)に従って更新する。

## Forgejoインストール完了スナップショット

`Forgejoインストール完了`は、[手動導入の再検証](installation-verification.md#分割した手順書による再検証2026-10-24)でForgejo 15.0.10とRunner 13.2.0の稼働、HTTP Git、hostジョブの成功を確認した後、VMを正常停止して作成した。既存の`OS準備完了`も保持している。復元時は対象VMだけを正常停止する。

```powershell
$vmx = 'C:\Users\ramse\Documents\Virtual Machines\forgejo-lab\forgejo-lab.vmx'
$vmrun = 'C:\Program Files\VMware\VMware Workstation\vmrun.exe'
& $vmrun -T ws stop $vmx soft
& $vmrun -T ws revertToSnapshot $vmx 'Forgejoインストール完了'
& $vmrun -T ws start $vmx nogui
ssh forgejo-lab 'systemctl is-active forgejo forgejo-runner-mydev'
```

VM内の初期管理者パスワードはスナップショット作成時点のものに戻る。対応するファイルはこのPCのGit管理外`C:\Users\ramse\.ssh\forgejo-admin-initial.txt`に保存した。復元後に管理者パスワードを変更した場合、この保存ファイルは一致しなくなるため、秘密情報の管理方針に従って扱う。
