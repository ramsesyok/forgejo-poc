# オンプレミス・エアギャップ環境へのForgejo 15.0 LTSとRunnerの手動導入

この文書は、**RHEL 8またはOracle Linux 8のオンプレミスサーバ**へ、人がコマンドを順に実行し、設定ファイルを編集してForgejoとRunnerを導入するマニュアルです。インストールスクリプトは使いません。[準備端末の手順](preparation.md)に従い、配布物と必要なRPMを対象サーバへ搬入してから本文を始めます。ForgejoとRunnerを同じサーバに置き、Runnerのジョブをコンテナなしで実行します。導入後の確認結果は実施者が記録します。

対象は既存の検証 VM の再現です。第5節では基盤検証用に `forgejo-admin` ユーザー単位の Runner を登録します。目的とする `myproject` 組織のリリース用リポジトリには、この登録をそのまま使えません。既存 VM での次の作業は[組織・Runner 登録手順](myproject-runner-registration.md)、続いて[ワークフロー導入手順](forgejo-workflow.md)へ進みます。文書全体の読み順は[README](README.md)を参照してください。

## 0. 対象と事前確認

| 項目 | 手順の前提 | 導入前に決める値 |
|---|---|---|
| OS | RHEL 8またはOracle Linux 8、x86_64、systemd・SELinux・firewalld利用 | ディストリビューション、マイナーバージョン、アーキテクチャ |
| Forgejo | 15.0.10（15.0 LTS） | 別版を使う場合は[15.xリリース一覧](https://forgejo.org/releases/15.x/)で選び、全ての版表記とハッシュを合わせる |
| Runner | 13.2.0 | 別版を使う場合は[Runnerリリース](https://code.forgejo.org/forgejo/runner/releases)で選ぶ |
| URL | 隔離LAN内のIPまたは内部DNS名、HTTPポート3000 | 実際の内部URL。内部TLSを使う場合は証明書と接続先 |
| 管理者 | `forgejo-admin` / `<内部管理用メールアドレス>` | 初期管理者名とメールアドレス |
| Runner登録範囲 | `forgejo-admin`所有リポジトリ | 信頼できる所有者 |
| Runnerラベル | `el8-mydev:host` | ワークフローは`runs-on: el8-mydev` |

Linuxユーザーの役割は、`devops`がSSHで入る管理者、`git`がForgejo本体とGitリポジトリへのSSHアクセス、`mydev`が手動ビルドとRunnerデーモン・ホスト実行ジョブです。`devops`は管理ユーザー名の例です。別名を使う場合は後述の`/home/devops/forgejo-install`をそのホームディレクトリへ置き換えます。`mydev`にはsudo権限を付けません。管理者が手動ビルドを行うときは`sudo -iu mydev`でシェルへ入り、CIと同じLinuxユーザーで確認します。

**先に[8. ForgejoとRunnerのオフライン設定](#8-forgejoとrunnerのオフライン設定)を確認します。** OSとネットワークの隔離設定はこの文書の対象外です。内部管理端末からSSH接続し、以降は特記しない限り**対象サーバのシェル**で操作します。`sudo`には管理ユーザーのパスワードが必要です。

```bash
cat /etc/os-release
uname -m
ip -4 -brief address
df -h /
getenforce
systemctl is-active sshd firewalld
sudo -v
test ! -e /usr/local/bin/forgejo && echo 'Forgejo未導入'
test ! -e /usr/local/bin/forgejo-runner && echo 'Runner未導入'
```

`/etc/os-release`の`ID`と`VERSION_ID`で対象OSと版を確認します。既存のForgejo/Runnerがあるサーバへは、この新規導入手順をそのまま適用しません。変更対象は`/usr/local/bin/forgejo*`、`/var/lib/forgejo`、`/etc/forgejo`、`/home/mydev`、systemdユニットとfirewalldです。

## 1. 依存パッケージ

ForgejoとRunnerが使用する`git`と`git-lfs`を、組織が用意した内部パッケージ供給元から導入します。`<内部リポジトリID>`を実際のIDへ置き換えます。複数の内部リポジトリが必要なら`--enablerepo`を各IDについて追加します。必要なRPMと依存関係が揃っていなければ、ここで止めて[準備端末の手順](preparation.md)に従い補充します。リポジトリ自体の設定はこの文書では扱いません。

```bash
sudo dnf --disablerepo='*' --enablerepo='<内部リポジトリID>' install -y git git-lfs
git --version
git lfs version
command -v gpg
```

内部リポジトリを使わず、準備端末から依存関係を含むRPM一式を搬入した場合は、RPM提供元の署名鍵のフィンガープリントを別経路で確認します。鍵がRPMデータベースに未登録なら、確認した鍵を`sudo rpm --import <署名鍵ファイル>`で登録してから`rpm -K`を実行します。Oracle Linux 8.10ではOS付属の`/etc/pki/rpm-gpg/RPM-GPG-KEY-oracle`の指紋`76FD 3DB1 3AB6 7410 B89D B10E 8256 2EA9 AD98 6DA3`を照合後に登録すると、搬入したOracle公式RPMの署名検証が通りました。Oracle Linux 8.10でこのRPM一式を使う場合のコマンドは次のとおりです。RHELでは利用するRPM供給元の鍵を確認してください。

```bash
gpg --show-keys --with-fingerprint /etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
sudo rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
```

すべてのRPMが`digests signatures OK`になってから、外部リポジトリを無効にして導入します。`<搬入先>`は実際のRPM配置先に置き換えます。異なるOS・マイナーバージョンで集めたRPMは流用しません。

```bash
RPM_DIR='/path/to/rpms'  # 実際の搬入先に変更
rpm -K "$RPM_DIR"/*.rpm
sudo dnf --disablerepo='*' install -y "$RPM_DIR"/*.rpm
git --version
git lfs version
```

`git-lfs`を含むRPMの提供元と版は、利用するディストリビューションの内部リポジトリで確認します。[Forgejo Runnerの公式要件](https://forgejo.org/docs/v15.0/admin/actions/installation/binary/)では、Git 2.24.3以上がテストされています。`gpg`は後述の署名検証に使用します。`command -v gpg`で見つからない場合だけ、内部リポジトリから`gnupg2`を導入します。`curl`は導入・常時稼働の依存パッケージではありません。

`gpg`がない場合だけ実行します。

```bash
sudo dnf --disablerepo='*' --enablerepo='<内部リポジトリID>' install -y gnupg2
```

## 2. 搬入済みファイルの確認と署名検証

[準備端末の手順](preparation.md)に従い、Forgejo 15.0.10とRunner 13.2.0のバイナリ、各`.asc`署名、Forgejo公開鍵、公式`forgejo.service`が管理ユーザーの`~/forgejo-install`に搬入済みであることを前提にします。ここでは`devops`を管理ユーザー名の例として使います。別名なら後続の`/home/devops/forgejo-install`を置き換えます。準備端末で別経路から確認した公開鍵フィンガープリントとSHA-256の記録を照合に使います。

```bash
cd "$HOME/forgejo-install"
test -s forgejo-15.0.10-linux-amd64
test -s forgejo-15.0.10-linux-amd64.asc
test -s forgejo-runner-13.2.0-linux-amd64
test -s forgejo-runner-13.2.0-linux-amd64.asc
test -s forgejo-release-key.asc
test -s forgejo.service
mkdir -m 700 "$HOME/forgejo-install/gnupg"
gpg --homedir "$HOME/forgejo-install/gnupg" --import forgejo-release-key.asc
gpg --homedir "$HOME/forgejo-install/gnupg" --fingerprint EB114F5E6C0DC2BCDD183550A4B61A2DC5923710
```

フィンガープリント`EB11 4F5E 6C0D C2BC DD18 3550 A4B6 1A2D C592 3710`と一致したら、両方で`Good signature`を確認します。GPGの「鍵の所有者を認証していない」警告は、公式サイトのフィンガープリントを別途照合して判断します。

```bash
gpg --homedir "$HOME/forgejo-install/gnupg" --verify forgejo-15.0.10-linux-amd64.asc forgejo-15.0.10-linux-amd64
gpg --homedir "$HOME/forgejo-install/gnupg" --verify forgejo-runner-13.2.0-linux-amd64.asc forgejo-runner-13.2.0-linux-amd64
sha256sum forgejo-15.0.10-linux-amd64 forgejo-15.0.10-linux-amd64.asc forgejo-runner-13.2.0-linux-amd64 forgejo-runner-13.2.0-linux-amd64.asc forgejo-release-key.asc forgejo.service
```

この版の照合値はForgejoが`eeb96095f610b6fbcd768e11b94cb345923f580d550d9cba44ee690d2a61daab`、Runnerが`fadaec897f5e6641c363f87ecaf75f866f99c81b7097ec6b433e4c48123fcad1`、公式`forgejo.service`が`3d93462a1a16dc8cd07b27d8b22d95ac67228cd6a93e97aac744bb120fc6a37f`です。搬入元で記録した値とも一致させます。版が違えばこのハッシュは使いません。

## 3. Forgejo本体とサービス

`sudo -i`でrootシェルへ入ります。`git`はForgejo専用のLinuxユーザーです。

```bash
sudo -i
groupadd --system git
useradd --system --create-home --home-dir /home/git --shell /bin/bash --comment 'Git Version Control' --gid git git
install -m 0755 /home/devops/forgejo-install/forgejo-15.0.10-linux-amd64 /usr/local/bin/forgejo
install -d -m 0750 -o git -g git /var/lib/forgejo /var/lib/forgejo/data /var/lib/forgejo/log
install -d -m 0770 -o root -g git /etc/forgejo
/usr/local/bin/forgejo --version
```

rootシェルで`vi /etc/forgejo/app.ini`を開き、次の内容を書きます。`APP_NAME`、`DOMAIN`、`SSH_DOMAIN`、`ROOT_URL`の山括弧付き部分を隔離LAN内の実際の値へ置き換えます。Runnerを別サーバへ置く場合は`DEFAULT_ACTIONS_URL`もRunnerから到達できる内部Forgejo URLへ置き換えます。初回起動でForgejoがトークン類を書き込めるよう、一時的に`0660`とします。

```ini
APP_NAME = <サーバ名>
RUN_USER = git
RUN_MODE = prod
WORK_PATH = /var/lib/forgejo

[database]
DB_TYPE = sqlite3
PATH = /var/lib/forgejo/data/forgejo.db

[repository]
ROOT = /var/lib/forgejo/data/forgejo-repositories
DISABLE_MIGRATIONS = true
DISABLE_HTTP_GIT = false

[server]
DOMAIN = <隔離LANのIPまたは内部DNS名>
SSH_DOMAIN = <隔離LANのIPまたは内部DNS名>
SSH_PORT = 22
HTTP_ADDR = 0.0.0.0
HTTP_PORT = 3000
ROOT_URL = http://<隔離LANのIPまたは内部DNS名>:3000/
LFS_START_SERVER = true
OFFLINE_MODE = true

[service]
DISABLE_REGISTRATION = true

[openid]
ENABLE_OPENID_SIGNIN = false
ENABLE_OPENID_SIGNUP = false

[security]
INSTALL_LOCK = true
DISABLE_WEBHOOKS = true

[mirror]
ENABLED = false

[actions]
ENABLED = true
DEFAULT_ACTIONS_URL = http://127.0.0.1:3000

[log]
ROOT_PATH = /var/lib/forgejo/log
```

`[repository] DISABLE_HTTP_GIT = false`により、3000/tcpへ到達できるクライアントは`http://<サーバ>:3000/<所有者>/<リポジトリ>.git`でGitのcloneとpushを利用できます。公開リポジトリのcloneは匿名で可能です。非公開リポジトリのcloneとpushには、利用者の認証と対象リポジトリへの権限が必要です。`DISABLE_REGISTRATION = true`は新規の自己登録を止める設定であり、既存ユーザーのGitアクセスは止めません。HTTPでは認証情報が暗号化されないため、実運用では内部HTTPSを推奨します。

```bash
chown root:git /etc/forgejo/app.ini
chmod 0660 /etc/forgejo/app.ini
```

Forgejo 15.0.10タグの[公式配布`forgejo.service`](https://codeberg.org/forgejo/forgejo/raw/tag/v15.0.10/contrib/systemd/forgejo.service)を変更せず配置します。準備端末から搬入したファイルが空でないこと、ユニットに`User=git`と`ExecStart=/usr/local/bin/forgejo web --config /etc/forgejo/app.ini`があること、SHA-256が準備端末で記録した値と一致することを確認します。

```bash
test -s /home/devops/forgejo-install/forgejo.service
sha256sum /home/devops/forgejo-install/forgejo.service
install -m 0644 /home/devops/forgejo-install/forgejo.service /etc/systemd/system/forgejo.service
test -s /etc/systemd/system/forgejo.service
grep -E '^(User=|ExecStart=|Environment=)' /etc/systemd/system/forgejo.service
sha256sum /etc/systemd/system/forgejo.service
restorecon -RF /usr/local/bin/forgejo /etc/forgejo /var/lib/forgejo /home/git
systemctl daemon-reload
systemctl enable --now forgejo.service
systemctl is-active forgejo.service
```

初回起動で`INTERNAL_TOKEN`、`LFS_JWT_SECRET`、`[oauth2] JWT_SECRET`が設定に生成されているか確認します。次の確認コマンドは**値を表示しません**。`INSTALL_LOCK = true`が1行だけあることも確認します。`SECRET_KEY`が既にあれば生成処理は行わず、ファイル権限の調整へ進みます。なければ続く生成処理を一度だけ実行します。

```bash
grep -E '^(INTERNAL_TOKEN|LFS_JWT_SECRET|JWT_SECRET) *=' /etc/forgejo/app.ini | cut -d= -f1
grep -n '^INSTALL_LOCK = true$' /etc/forgejo/app.ini
grep -n '^SECRET_KEY *=' /etc/forgejo/app.ini | cut -d: -f1
```

`SECRET_KEY`がない場合だけ次を実行します。

```bash
systemctl stop forgejo.service
secret=$(/usr/local/bin/forgejo generate secret SECRET_KEY)
test -n "$secret"
sed -i "/^INSTALL_LOCK = true$/a SECRET_KEY = $secret" /etc/forgejo/app.ini
unset secret
grep -E '^SECRET_KEY *=' /etc/forgejo/app.ini | cut -d= -f1
```

その後、権限を絞ってForgejoを起動します。

```bash
chown root:git /etc/forgejo/app.ini
chmod 0640 /etc/forgejo/app.ini
chmod 0750 /etc/forgejo
restorecon -RF /etc/forgejo
systemctl start forgejo.service
systemctl is-active forgejo.service
```

`app.ini`とSQLite DBの秘密情報はGitへ追加しません。firewalldは有効のまま3000/tcpを許可し、SSHの許可を保持します。`firewall-cmd --get-active-zones`で対象NICのゾーンを確認し、以下の`<隔離LANのゾーン名>`をその値へ置き換えます。`public`などのゾーン名を決め打ちしません。[RHEL 8のfirewalldゾーン手順](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/securing_networks/using-and-configuring-firewalld_securing-networks)

```bash
firewall-cmd --get-active-zones
firewall-cmd --permanent --zone=<隔離LANのゾーン名> --add-port=3000/tcp
firewall-cmd --reload
firewall-cmd --zone=<隔離LANのゾーン名> --list-all
getenforce
```

## 4. 初期管理者

rootシェルでForgejo CLIを`git`として実行します。管理者名とメールを置き換えます。以下の`admin@internal.example`は記入例であり、組織が管理する内部メールアドレスを指定します。メール送信が必要な運用では別途内部SMTPを設定します。ランダムパスワードをroot専用ファイルに保存し、SCPで準備端末のGit管理外へ取得します。シェル履歴やGitには書きません。

```bash
umask 077
runuser -u git -- /usr/local/bin/forgejo -w /var/lib/forgejo -c /etc/forgejo/app.ini \
  admin user create --username forgejo-admin --email admin@internal.example --admin \
  --random-password --random-password-length 24 > /root/forgejo-admin-initial.txt
chmod 0600 /root/forgejo-admin-initial.txt
runuser -u git -- /usr/local/bin/forgejo -w /var/lib/forgejo -c /etc/forgejo/app.ini admin user list
install -m 0600 -o devops -g devops /root/forgejo-admin-initial.txt /home/devops/forgejo-admin-initial.txt
```

`IsAdmin=true`を確認したら、[準備端末の「初期パスワードの受け取り」](preparation.md#5-初期パスワードの受け取り)を実施します。準備端末のGit管理外に保存できたことを確認してから、対象サーバのrootシェルで一時ファイルを消します。生成出力の先頭行にある`generated random password is '...'`の引用符内24文字が初期パスワードです。秘密値を画面や作業ログへ出さず、初回ログイン時に変更します。

```bash
rm -f /root/forgejo-admin-initial.txt /home/devops/forgejo-admin-initial.txt
```

## 5. 検証用ビルドユーザーとユーザー単位Runnerの配置・登録

引き続きrootシェルで操作します。`mydev`はこのプロダクトの手動ビルド用Linuxユーザーです。Runnerサービスとhostジョブも同じユーザーで動かします。`wheel`へ追加せず、パスワードを設定しない初期状態にします。管理者は`sudo -iu mydev`で手動ビルドできます。hostジョブは`mydev`のホームにあるファイルも読めるため、個人用の秘密鍵やパスワードは置きません。

```bash
install -m 0755 /home/devops/forgejo-install/forgejo-runner-13.2.0-linux-amd64 /usr/local/bin/forgejo-runner
useradd --create-home --home-dir /home/mydev --shell /bin/bash --comment 'Manual and CI build user' mydev
passwd -l mydev
install -d -m 0700 -o mydev -g mydev /home/mydev/runner-work
/usr/local/bin/forgejo-runner --version
id mydev
runuser -l mydev -c 'whoami; pwd'
```

サーバ内で40桁の登録シークレットを生成します。`printf`を使い、ファイル末尾に改行を入れません。`--scope forgejo-admin`を必ず指定し、インスタンス全体には登録しません。[Forgejo CLI](https://forgejo.org/docs/v15.0/admin/command-line/)の`actions register`が出力する**UUID**を控えます。40桁の登録シークレットは`uuid`ではなく、`token_url`が参照するファイルの内容です。シークレットは表示しません。

```bash
umask 077
secret=$(runuser -u git -- /usr/local/bin/forgejo -w /var/lib/forgejo -c /etc/forgejo/app.ini forgejo-cli actions generate-secret)
test "$(printf '%s' "$secret" | wc -c)" -eq 40
printf '%s' "$secret" > /var/lib/forgejo/runner-secret
chown git:git /var/lib/forgejo/runner-secret
unset secret
runuser -u git -- /usr/local/bin/forgejo -w /var/lib/forgejo -c /etc/forgejo/app.ini \
  forgejo-cli actions register --name forgejo-mydev --scope forgejo-admin \
  --labels el8-mydev --secret-file /var/lib/forgejo/runner-secret
install -m 0600 -o mydev -g mydev /var/lib/forgejo/runner-secret /home/mydev/runner-token
rm -f /var/lib/forgejo/runner-secret
```

rootシェルで`vi /home/mydev/runner-config.yml`を開き、次の内容を書く。`uuid`は直前のCLI出力へ**必ず置換**する。40桁の登録シークレットを貼らない。`token_url`で`0600`の秘密ファイルを参照し、設定ファイルにトークン本文を書かない。[Runner設定](https://forgejo.org/docs/v15.0/admin/actions/configuration/)の`host`ラベルはコンテナなしの実行方式です。

`forgejo-runner-mydev.service`の`WorkingDirectory=/home/mydev`は**デーモンの起動ディレクトリ**です。ジョブの作業ディレクトリの親は下記`host.workdir_parent: /home/mydev/runner-work`で指定します。ジョブ固有の子ディレクトリと`FORGEJO_WORKSPACE`の実際の値はジョブ実行時に決まります。[Forgejo Actionsの参照資料](https://forgejo.org/docs/v15.0/user/actions/reference/)では`FORGEJO_WORKSPACE`をステップの既定作業ディレクトリとしています。`working-directory`の指定やステップ内の`cd`で移動できます。

```yaml
log:
  level: info
runner:
  capacity: 1
  labels:
    - el8-mydev:host
  insecure: false
cache:
  enabled: false
host:
  workdir_parent: /home/mydev/runner-work
server:
  connections:
    local:
      url: http://127.0.0.1:3000/
      uuid: <登録コマンドが返したUUID>
      token_url: file:/home/mydev/runner-token
```

```bash
chown mydev:mydev /home/mydev/runner-config.yml
chmod 0600 /home/mydev/runner-config.yml
grep -Eq '^      uuid: ([[:xdigit:]]{32}|[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12})$' /home/mydev/runner-config.yml
```

最後の`grep`が失敗した場合は、Runnerを起動する前に`uuid`の値を確認します。CLIの出力を控え忘れた場合は、rootシェルで以下を実行して同じRunnerのUUIDを再表示できます。`actions register`は同じシークレットで再実行できます。表示されたUUIDを`runner-config.yml`へ設定し、再び`grep`で確認します。シークレット本文は表示しません。

```bash
install -m 0600 -o git -g git /home/mydev/runner-token /var/lib/forgejo/runner-secret
runuser -u git -- /usr/local/bin/forgejo -w /var/lib/forgejo -c /etc/forgejo/app.ini \
  forgejo-cli actions register --name forgejo-mydev --scope forgejo-admin \
  --labels el8-mydev --secret-file /var/lib/forgejo/runner-secret
rm -f /var/lib/forgejo/runner-secret
```

rootシェルで`vi /etc/systemd/system/forgejo-runner-mydev.service`を開き、次のユニットを書く。

```ini
[Unit]
Description=Forgejo Actions Runner for mydev (host execution)
Wants=network-online.target
Requires=forgejo.service
After=network-online.target forgejo.service

[Service]
Type=simple
User=mydev
Group=mydev
WorkingDirectory=/home/mydev
Environment=HOME=/home/mydev
ExecStart=/usr/local/bin/forgejo-runner daemon -c /home/mydev/runner-config.yml
Restart=always
RestartSec=5s
NoNewPrivileges=true
ProtectSystem=full
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

```bash
chmod 0644 /etc/systemd/system/forgejo-runner-mydev.service
restorecon -RF /usr/local/bin/forgejo-runner /home/mydev /etc/systemd/system/forgejo-runner-mydev.service
systemctl daemon-reload
systemctl enable --now forgejo-runner-mydev.service
systemctl is-active forgejo-runner-mydev.service
journalctl -u forgejo-runner-mydev.service -n 30 --no-pager
exit
```

ログに`declared successfully`、`labels: [el8-mydev]`、`[poller] launched`が出ることを確認します。**上記の登録コマンドで`--scope forgejo-admin`を指定したため、このRunnerは`forgejo-admin`ユーザー単位で登録されています。追加の対象設定は不要です。** 対象は`forgejo-admin`自身が所有するリポジトリのワークフローで、管理権限を持つだけの別ユーザー・組織のリポジトリは含みません。[Runner登録ガイド](https://forgejo.org/docs/v15.0/admin/actions/registration/) Web画面では`forgejo-admin`でログインし、ユーザー設定の`Actions > Runners`でオンライン状態を確認できます。

この登録は検証 VM の基盤動作を確かめるためのものです。`myproject` にリリース用リポジトリを置く際は、[組織・Runner 登録手順](myproject-runner-registration.md)で組織単位の接続を追加します。

### 複数の手動ビルド環境を置く場合

例えば2製品目を`mydev2`で手動ビルドするなら、Runnerサービスも`forgejo-runner-mydev2.service`として**別プロセス**にします。2製品目専用の登録、設定・トークン、作業ディレクトリ、`el8-mydev2:host`のような固有ラベルを用意し、サービスの`User=`と`Group=`を`mydev2`にします。対象リポジトリだけに登録すると、別製品のジョブが誤った環境を選びにくくなります。同じサーバ上のhostジョブは強い隔離を持たないため、信頼境界を分けたい場合はサーバ自体も分けます。

## 6. 管理端末と再起動後の確認

隔離LAN内の管理端末から、ブラウザーで`http://<内部DNS名またはIP>:3000/`にアクセスし、管理者ログインと画面表示を確認します。APIの版を確認する場合は、同じブラウザーで`http://<内部DNS名またはIP>:3000/api/v1/version`を開きます。以下はSSH確認のシェル例です。`forgejo.internal.example`を実際の内部DNS名またはIPへ置き換えます。管理端末にも外部ネットワークへの中継経路を設けません。複数人が利用するサーバでは、内部CAで発行した証明書を使うHTTPSも検討します。

```bash
FORGEJO_HOST='forgejo.internal.example'
ssh "devops@${FORGEJO_HOST}" 'cat /etc/os-release; getenforce; systemctl is-active forgejo forgejo-runner-mydev sshd firewalld'
```

対象サーバで次もrootとして確認します。`app.ini`は`root:git 640`、Runnerの設定とトークンは`mydev:mydev 600`を期待します。秘密値そのものは表示しません。`<隔離LANのゾーン名>`は手順3で確認した値へ置き換えます。

```bash
systemctl is-enabled forgejo forgejo-runner-mydev
stat -c '%U:%G %a %n' /etc/forgejo/app.ini /home/mydev/runner-config.yml /home/mydev/runner-token
firewall-cmd --zone=<隔離LANのゾーン名> --list-all
journalctl -u forgejo-runner-mydev.service -n 30 --no-pager
```

再起動後も`forgejo`と`forgejo-runner-mydev`が`active`になることを確認します。起動直後にRunnerがForgejoへの接続を一度失敗しても、ユニットが5秒後に再試行します。最終的に`declared successfully`と`[poller] launched`を確認します。

Runnerのジョブ実行まで試す場合、`forgejo-admin`所有の検証リポジトリへ`.forgejo/workflows/host-smoke.yml`を追加します。ホスト実行なので、信頼できるワークフローだけを登録します。

```yaml
name: host-smoke
on: push
jobs:
  smoke:
    runs-on: el8-mydev
    steps:
      - run: |
          whoami
          pwd
          printf '%s\n' "$FORGEJO_WORKSPACE"
          cat /etc/os-release
          test "$(whoami)" = mydev
          test -w "$FORGEJO_WORKSPACE"
          printf 'built by %s\n' "$(whoami)" > build-artifact.txt
          test -s build-artifact.txt
          printf 'user=%s\nworkspace=%s\n' "$(whoami)" "$FORGEJO_WORKSPACE" > /home/mydev/runner-work/identity-check.txt
```

期待結果は`whoami`が`mydev`、OSが導入対象のRHEL 8またはOracle Linux 8です。`pwd`と`FORGEJO_WORKSPACE`で実際のジョブディレクトリを確かめます。ジョブ成功後、対象サーバで`sudo stat -c '%U:%G %n' /home/mydev/runner-work/identity-check.txt`と`sudo cat /home/mydev/runner-work/identity-check.txt`を実行すると、実行ユーザーと作業パスを再確認できます。`build-artifact.txt`はジョブ内の書き込み確認に使います。検証後に不要なら`sudo rm /home/mydev/runner-work/identity-check.txt`で記録ファイルを消します。

ビルド対象のソースは自動では配置されません。[公式クイックスタート](https://forgejo.org/docs/v15.0/user/actions/quick-start/)のように`actions/checkout`を追加して取得します。その場合は必要なActionを先に内部Forgejoへ搬入し、ワークフローで参照する版を固定します。`DEFAULT_ACTIONS_URL`は上記の設定で内部Forgejoを指しています。実際の製品ビルドに必要なランタイム・ツールと依存物は製品ごとに搬入します。systemd起動のRunnerは手動ログイン時のシェル初期化ファイルを通常は読み込まないため、ビルドに必要な`PATH`と環境変数をワークフローまたはサービス設定で明示し、実ジョブで確認します。

## 7. 導入結果の記録と運用上の注意

導入ごとに、次の結果を運用記録へ残します。秘密値そのものは記録せず、Gitにも追加しません。

| 確認項目 | 記録する結果 |
|---|---|
| OSとパッケージ | `/etc/os-release`、`uname -m`、導入した`git`・`git-lfs`の版 |
| 搬入ファイル | バイナリと公式unitのSHA-256、署名検証結果、公開鍵フィンガープリント |
| Forgejo | `/api/v1/version`の応答、`forgejo.service`の有効・稼働状態、管理者の作成とログイン、内部URLからのアクセス |
| Runner | 版、`forgejo-runner-mydev.service`の有効・稼働状態、ユーザー単位の登録、`el8-mydev`ラベル、ジョブ成功 |
| OSの保護 | SELinuxが`Enforcing`、firewalldが有効、対象ゾーンでSSHと3000/tcpを許可、`mydev`にsudo権限がないこと |
| ビルド環境 | `sudo -iu mydev`での手動ビルド結果、ジョブの`whoami`・`FORGEJO_WORKSPACE`・成果物の所有者 |
| オフライン設定 | [8. ForgejoとRunnerのオフライン設定](#8-forgejoとrunnerのオフライン設定)の確認結果 |

`host`方式はジョブをサーバ上で直接実行し、ジョブ間の強い隔離を提供しません。[公式Runner設定](https://forgejo.org/docs/v15.0/admin/actions/configuration/)の警告に従い、信頼できないPRのワークフローや第三者のリポジトリには使用しません。バックアップは`/etc/forgejo/app.ini`と`/var/lib/forgejo`を整合した時点で一緒に取得します。更新時は[公式アップグレード手順](https://forgejo.org/docs/v15.0/admin/upgrade/)を参照します。内部IPまたはDNS名が変わったら`DOMAIN`、`SSH_DOMAIN`、`ROOT_URL`と管理端末のSSH接続先を更新します。

## 8. ForgejoとRunnerのオフライン設定

この節は**Forgejo、Forgejo Runner、Actionsジョブがインターネット上のサービスを参照しないための設定**を確認します。OSやネットワークの隔離方法は扱いません。

`DISABLE_MIGRATIONS = true` はこの検証 VM の通常設定です。既存の GitLab などから一度だけリポジトリを移行する場合は、[ワークフロー導入手順の移行方法](forgejo-workflow.md#既存の-gitlab-などから移行する場合)に従って移行元への接続と設定変更を行います。

[Forgejo 15.0設定一覧](https://forgejo.org/docs/v15.0/admin/config-cheat-sheet/)によると、`OFFLINE_MODE = true`はCDNとGravatarの利用を止めます。一方、`[actions] DEFAULT_ACTIONS_URL`の既定値は外部URLで、`[mirror] ENABLED`の既定値は`true`です。[Actions管理者ガイド](https://forgejo.org/docs/v15.0/admin/actions/)によると、相対指定の`uses:`は`DEFAULT_ACTIONS_URL`を基準に解決されます。本文の`app.ini`ではこれらを明示的に内部向けへ変更しています。

| 対象 | 本文で指定する設定と確認内容 |
|---|---|
| Forgejoの画面 | `[server] OFFLINE_MODE = true`。`DOMAIN`、`SSH_DOMAIN`、`ROOT_URL`は内部アドレス。 |
| 外部サービス機能 | `[repository] DISABLE_MIGRATIONS = true`、`[mirror] ENABLED = false`、`[security] DISABLE_WEBHOOKS = true`、`[openid] ENABLE_OPENID_SIGNIN = false`・`ENABLE_OPENID_SIGNUP = false`。外部SMTP、認証先、オブジェクトストレージなどを追加しない。 |
| Actionsの取得先 | `[actions] DEFAULT_ACTIONS_URL = http://127.0.0.1:3000`。利用するActionを同じForgejoへ事前に搬入し、ワークフローでは内部リポジトリと版を指定する。 |
| Runner | `server.connections.local.url = http://127.0.0.1:3000/`、`cache.enabled = false`。Runner自身の接続先を同一サーバのForgejoに限定する。 |
| ジョブ | `uses:`の絶対URL、Git/LFSリモート、`.gitmodules`、ビルドツールの依存取得先を確認し、内部サービスまたは搬入済みファイルのみ参照する。 |

設定確認では秘密値を表示・記録しません。`[actions] DEFAULT_ACTIONS_URL`とRunnerの`url`がどちらもローカルForgejoを指し、内部に搬入したActionを使うジョブが成功することを確認します。

```bash
grep -nE '^\[|^(OFFLINE_MODE|DISABLE_MIGRATIONS|ENABLE_OPENID_SIGNIN|ENABLE_OPENID_SIGNUP|DISABLE_WEBHOOKS|ENABLED|DEFAULT_ACTIONS_URL|DOMAIN|SSH_DOMAIN|ROOT_URL) *=' /etc/forgejo/app.ini
grep -nE '^cache:|^  enabled:|^server:|^  connections:|^      url:' /home/mydev/runner-config.yml
systemctl is-active forgejo forgejo-runner-mydev
```

`OFFLINE_MODE`や`DEFAULT_ACTIONS_URL`は、ワークフロー内の任意コマンドや絶対URLを指定したActionの通信先までは制限しません。host方式のジョブは`mydev`としてコマンドを実行するため、ジョブとビルド依存物の参照先は製品ごとに確認します。
