# forgejo-lab 導入手順の検証記録

実施日: 2026-10-24。汎用の手動手順は [`../preparation.md`](../preparation.md) と [`../installation.md`](../installation.md) を参照する。この記録に秘密値は含めない。

## 復元と準備端末

- VMware Workstation の `forgejo-lab` だけを停止し、既存スナップショット「OS準備完了」に復元して起動した。復元後のSSH接続先は `192.168.131.131` のままだった。
- 復元直後は Oracle Linux 8.10、SELinux `Enforcing`、`sshd` と `firewalld` は `active`。Forgejo、Runner、`git`、`git-lfs` は未導入だった。
- 準備端末はこのWindows PC。搬入ファイルは `C:\Users\ramse\Downloads\forgejo-airgap-15.0.10` に保存し、SCPで `/home/devops/forgejo-install` へ送った。Forgejo/Runnerの取得コマンドをVM内では実行していない。
- Oracle公式リポジトリの `git`、`git-lfs` と依存RPM計49個を準備端末に取得し、`rpms` サブフォルダに保存した。URL一覧は同フォルダの `source-urls.txt`。VMに搬入後、OS付属のOracle公開鍵（指紋 `76FD 3DB1 3AB6 7410 B89D B10E 8256 2EA9 AD98 6DA3`）をRPMデータベースに登録し、49個すべてで `rpm -K` の署名検証が通った。`dnf --disablerepo='*' install` により搬入RPMだけで導入した。結果は Git 2.43.7、Git LFS 3.4.1。

## 公式ファイルの取得と検証

| ファイル | 準備端末での入手元 | SHA-256 |
|---|---|---|
| `forgejo-15.0.10-linux-amd64` | CodebergのForgejo v15.0.10リリース | `eeb96095f610b6fbcd768e11b94cb345923f580d550d9cba44ee690d2a61daab` |
| `forgejo-runner-13.2.0-linux-amd64` | 公式Runner 13.2.0リリースの通常配布URLからWindowsの`curl.exe`で取得 | `fadaec897f5e6641c363f87ecaf75f866f99c81b7097ec6b433e4c48123fcad1` |
| `forgejo.service` | Forgejo v15.0.10タグの公式配布ファイル | `3d93462a1a16dc8cd07b27d8b22d95ac67228cd6a93e97aac744bb120fc6a37f` |

Forgejo/Runnerの各`.asc`と公開鍵も準備端末に保存して搬入した。公開鍵指紋は `EB11 4F5E 6C0D C2BC DD18 3550 A4B6 1A2D C592 3710`。VM上のGPG検証で両バイナリとも `Good signature`、SHA-256は準備端末とVMで一致した。最初の`Invoke-WebRequest`とブラウザーでRunnerの通常配布URLを開いたときは自動アクセス確認用HTMLが返った。後からWindows標準の`curl.exe --fail --location`で直接取得すると、バイナリは22,290,594バイト、署名は228バイトで、既に検証済みのファイルとバイト単位で一致した。直接取得した2ファイルを再搬入してGPG署名とSHA-256を再検証した。

## 導入結果

- Forgejo 15.0.10を導入。`forgejo.service`は公式ファイルのままで、配置後も上記ハッシュと一致。`app.ini`は `root:git 640`。ホストPCから `http://192.168.131.131:3000/api/v1/version` が `15.0.10+gitea-1.22.0` を返した。
- `forgejo-admin`（`admin@internal.example`）を管理者として作成。初期パスワード生成結果をVMからSCPでこのPCのGit管理外へ取得し、24文字のパスワードを `C:\Users\ramse\.ssh\forgejo-lab-forgejo-admin-password.txt` に保存した。ACLは `ramse` のみ。SCP用の一時ファイルとVM内の一時ファイルは確認後に削除した。ホストPCからそのパスワードで管理者API認証に成功した。
- `mydev` を作成し、`forgejo-runner-mydev.service` を `mydev` で起動。Runnerは v13.2.0、`forgejo-admin` 所有範囲、ラベル `el8-mydev:host`。ログで `declared successfully` と `[poller] launched` を確認。`mydev` はsudoを実行できない。
- `forgejo-admin/runner-host-smoke` という非公開の検証リポジトリを作成。ホストPCからHTTPでcloneとpushに成功。pushを契機とする `host-smoke` ジョブは `success`。ジョブの記録は `user=mydev`、`FORGEJO_WORKSPACE=/home/mydev/runner-work/44ac21f7a61b29ee/hostexecutor`。記録ファイルは `mydev:mydev` 所有。
- firewalld `public` ゾーンでは `ssh` と `3000/tcp` を許可し、SELinuxは `Enforcing`。Forgejoの `OFFLINE_MODE=true`、外部移行・ミラー・Webhook・OpenIDの無効化、Actionsの内部URLを設定値で確認した。HTTP Gitは有効。
- 再起動後、`forgejo` と `forgejo-runner-mydev` は `enabled` かつ `active`。RunnerはForgejoの起動前に一度接続失敗したが、5秒後の再試行で登録とpoller起動に成功。ホストPCからのAPI応答も再確認した。

この検証VMのNICはNATのままであり、物理的なエアギャップ環境そのものの検証ではない。実ファイルの搬入、外部リポジトリ無効でのRPM導入、Forgejo/Runnerのアプリケーション設定と動作を確認した。

## 分割した手順書による再検証（2026-10-24）

- `forgejo-lab`を正常停止し、唯一のスナップショット「OS準備完了」へ復元して起動した。復元直後はOracle Linux 8.10、Forgejo/Runner未導入、SELinux `Enforcing`、`sshd`・`firewalld`稼働を確認した。他のVMは操作していない。
- [`preparation.md`](../preparation.md) の6つの公式URLから、このWindows PCの`curl.exe --fail --location`でForgejo 15.0.10、Runner 13.2.0、各署名、公開鍵、公式`forgejo.service`を再取得した。6ファイルのサイズとSHA-256は同文書の表とすべて一致した。再取得ファイルをGit管理外の`C:\Users\ramse\Downloads\forgejo-airgap-15.0.10-recheck`にまとめ、前回取得済みのOracle Linux 8.10用RPM 49個とともにSCPで`/home/devops/forgejo-install`へ搬入した。RPMの取得自体は今回再実施していない。
- 対象VMでForgejo/RunnerのGPG署名は両方`Good signature`、公開鍵指紋は`EB11 4F5E 6C0D C2BC DD18 3550 A4B6 1A2D C592 3710`、6ファイルのSHA-256はWindows上の値と一致した。
- 復元直後に`rpm -K`を実行すると、49個すべてが`SIGNATURES NOT OK`になった。OS付属のOracle RPM署名鍵の指紋`76FD 3DB1 3AB6 7410 B89D B10E 8256 2EA9 AD98 6DA3`を照合して`rpm --import`で登録したところ、49個すべてが`digests signatures OK`になった。この必須手順を[`installation.md`の第1節](../installation.md#1-依存パッケージ)へ追記した。`dnf --disablerepo='*' install`で搬入RPMだけを使い、Git 2.43.7とGit LFS 3.4.1を導入した。
- [`installation.md`](../installation.md) の設定内容に従い、Forgejo 15.0.10を配置した。公式`forgejo.service`は搬入元・配置先ともSHA-256が`3d93462a1a16dc8cd07b27d8b22d95ac67228cd6a93e97aac744bb120fc6a37f`で一致し、未変更。設定ファイルの内容は文書のコードブロックから内部IP `192.168.131.131`を代入した。SSH越しに`sudo -S`を用いて各コマンドを実行し、ファイル編集は文書の`vi`操作と同じ内容を`tee`で書き込んだ。
- `forgejo-admin`（`admin@internal.example`）を管理者として作成し、管理者API認証が成功した。初期パスワードはVM上の一時ファイルからSCPでこのPCのGit管理外`C:\Users\ramse\.ssh\forgejo-admin-initial.txt`に保存。24文字であること、ACLが`YOK_GAME01\ramse:(F)`のみであることを秘密値を表示せずに確認し、VM上の一時ファイルを削除した。
- Runner v13.2.0を`mydev`で起動し、`forgejo-admin`所有範囲・ラベル`el8-mydev:host`で登録した。ログに`declared successfully`と`[poller] launched`を確認。`sudo -iu mydev`で手動ビルドユーザーへ切り替えると`whoami=mydev`、作業場所`/home/mydev`、Git 2.43.7。Windowsから非公開の`forgejo-admin/runner-host-smoke`をHTTPでclone・pushし、手順書の`host-smoke`ジョブが`success`。`identity-check.txt`は`mydev:mydev`所有で、内容は`user=mydev`、`workspace=/home/mydev/runner-work/999ca3eedb5e1ec8/hostexecutor`。`mydev`はsudo不可。
- 再起動後、`forgejo`と`forgejo-runner-mydev`、`sshd`、`firewalld`はいずれも`active`。Forgejo/Runnerは`enabled`、SELinuxは`Enforcing`。RunnerはForgejoの起動前に一度接続失敗し、5秒後に登録とpoller起動に成功した。ホストから`/api/v1/version`が`15.0.10+gitea-1.22.0`を返した。設定ファイルは`root:git 640`、Runner設定とトークンは`mydev:mydev 600`。Forgejoの`OFFLINE_MODE=true`、Actionsの内部URL、RunnerのローカルURLとキャッシュ無効を確認した。

この再検証はアプリケーション設定と搬入方式を確認したもの。VMのNICはNATであり、外部通信が物理的に遮断された実サーバでの検証は別途必要。

## Forgejoインストール完了スナップショット

再検証後のVMを正常停止し、`Forgejoインストール完了`を作成した。`vmrun listSnapshots`で既存の`OS準備完了`と新しいスナップショットの両方を確認した。作成後にVMを起動し、Forgejo・Runner・sshd・firewalldが`active`、SELinuxが`Enforcing`、ホストからのAPI応答が`15.0.10+gitea-1.22.0`であることを確認した。
