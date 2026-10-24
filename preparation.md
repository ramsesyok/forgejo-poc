# 準備端末でのForgejo 15.0 LTS・Runner配布物の準備

この文書は、インターネットに接続できる**Windowsの準備端末**で配布物を取得し、RHEL 8またはOracle Linux 8のオンプレミス対象サーバへ搬入する手順です。対象サーバから外部サイトへアクセスしません。対象サーバへの搬入を終えたら[導入手順](installation.md)を実施します。手順はPowerShellで人が順に実行します。リリース用リポジトリまでの全体の流れは[README](README.md)にまとめています。

## 1. 準備する値と保存先

対象サーバのディストリビューション、マイナーバージョン、x86_64であることを確認します。SSH接続先と管理ユーザーを決め、対象サーバのSSHホスト鍵のフィンガープリントを別経路で確認してから接続します。以下の`devops`とホスト名は例です。配布物と初期パスワードの保存先はGit作業ツリーの外にします。

```powershell
$FORGEJO_HOST = 'forgejo.internal.example'  # 対象サーバの内部DNS名またはIPへ変更
$FORGEJO_USER = 'devops'                    # 対象サーバの管理ユーザーへ変更
$STAGE = Join-Path $HOME 'Downloads\forgejo-airgap-15.0.10'
New-Item -ItemType Directory -Force -Path $STAGE | Out-Null
Set-Location $STAGE
```

`$STAGE`には秘密情報を入れません。インターネットと隔離LANが分離されていてSCPで直接搬入できない場合は、組織が承認した媒体・転送経路を使い、同じファイル名で対象サーバの`~/forgejo-install`へ配置します。

## 2. 公式配布物を取得する

[Forgejo 15.0.10リリース](https://codeberg.org/forgejo/forgejo/releases/tag/v15.0.10)、[Runner 13.2.0リリース](https://code.forgejo.org/forgejo/runner/releases/tag/v13.2.0)、15.0.10タグの[公式systemdユニット](https://codeberg.org/forgejo/forgejo/raw/tag/v15.0.10/contrib/systemd/forgejo.service)、[Forgejo署名鍵](https://keys.openpgp.org/vks/v1/by-fingerprint/EB114F5E6C0DC2BCDD183550A4B61A2DC5923710)を取得します。PowerShellでは`curl`という別名を避けて`curl.exe`を指定します。各行の実行後、`$LASTEXITCODE`が0でない場合は次へ進みません。

```powershell
curl.exe --fail --location --show-error --output forgejo-15.0.10-linux-amd64 https://codeberg.org/forgejo/forgejo/releases/download/v15.0.10/forgejo-15.0.10-linux-amd64
curl.exe --fail --location --show-error --output forgejo-15.0.10-linux-amd64.asc https://codeberg.org/forgejo/forgejo/releases/download/v15.0.10/forgejo-15.0.10-linux-amd64.asc
curl.exe --fail --location --show-error --output forgejo-runner-13.2.0-linux-amd64 https://code.forgejo.org/forgejo/runner/releases/download/v13.2.0/forgejo-runner-13.2.0-linux-amd64
curl.exe --fail --location --show-error --output forgejo-runner-13.2.0-linux-amd64.asc https://code.forgejo.org/forgejo/runner/releases/download/v13.2.0/forgejo-runner-13.2.0-linux-amd64.asc
curl.exe --fail --location --show-error --output forgejo-release-key.asc https://keys.openpgp.org/vks/v1/by-fingerprint/EB114F5E6C0DC2BCDD183550A4B61A2DC5923710
curl.exe --fail --location --show-error --output forgejo.service https://codeberg.org/forgejo/forgejo/raw/tag/v15.0.10/contrib/systemd/forgejo.service
```

## 3. 取得結果を確認する

HTTP応答が成功しても、自動アクセス確認用のHTMLが保存される場合があります。次のサイズとSHA-256を確認し、一致しないファイルを搬入しません。Runnerの通常配布ファイルは、このWindows端末で`curl.exe --fail --location`による取得を確認しました。ブラウザーや`Invoke-WebRequest`で8 KB程度のファイルになった場合は、そのファイルを使いません。

```powershell
Get-Item forgejo-15.0.10-linux-amd64, forgejo-15.0.10-linux-amd64.asc, forgejo-runner-13.2.0-linux-amd64, forgejo-runner-13.2.0-linux-amd64.asc, forgejo-release-key.asc, forgejo.service | Select-Object Name, Length
Get-FileHash -Algorithm SHA256 forgejo-15.0.10-linux-amd64, forgejo-15.0.10-linux-amd64.asc, forgejo-runner-13.2.0-linux-amd64, forgejo-runner-13.2.0-linux-amd64.asc, forgejo-release-key.asc, forgejo.service
```

| ファイル | この版で確認したサイズ | この版で確認したSHA-256 |
|---|---:|---|
| `forgejo-15.0.10-linux-amd64` | 116,555,752バイト | `eeb96095f610b6fbcd768e11b94cb345923f580d550d9cba44ee690d2a61daab` |
| `forgejo-15.0.10-linux-amd64.asc` | 228バイト | `03511ba2ca50e2c9c301db6369e4b84b6f6bdf0ea7125c3e14d6673e923f2172` |
| `forgejo-runner-13.2.0-linux-amd64` | 22,290,594バイト | `fadaec897f5e6641c363f87ecaf75f866f99c81b7097ec6b433e4c48123fcad1` |
| `forgejo-runner-13.2.0-linux-amd64.asc` | 228バイト | `4741d81f613b32ddde1fa550ec8eefebfadeb07f3ab3dd7589ffd32cbb23addd` |
| `forgejo-release-key.asc` | 4,334バイト | `680195dfbf564a03b9fc72a3e2b35f193b5f043df2a7b1385f4994b2efd27531` |
| `forgejo.service` | 2,500バイト | `3d93462a1a16dc8cd07b27d8b22d95ac67228cd6a93e97aac744bb120fc6a37f` |

6ファイルすべてのSHA-256を作業記録に控え、対象サーバでも照合します。版を変更した場合は上表のサイズ・ハッシュを流用しません。[Forgejo公式ダウンロード案内](https://forgejo.org/download/)にある署名鍵フィンガープリント`EB11 4F5E 6C0D C2BC DD18 3550 A4B6 1A2D C592 3710`を確認し、対象サーバの担当者へ別経路でも伝えます。GPG署名の検証は搬入後に[導入手順の第2節](installation.md#2-搬入済みファイルの確認と署名検証)で行います。

## 4. 必要なRPM・Actionを揃えて搬入する

対象サーバに組織の内部RPMリポジトリがある場合、`git`と`git-lfs`はそこから導入します。`gpg`がない場合だけ`gnupg2`も必要です。内部リポジトリがない場合は、対象サーバと同じディストリビューション・マイナーバージョン・アーキテクチャ向けのRPMを、依存関係を含めて組織の承認済み供給元から収集し、`$STAGE\rpms`に置きます。Windows単体で依存関係を推測せず、同じOS条件のパッケージ管理環境またはパッケージ管理者が解決した一式を使用します。RPMの署名鍵・フィンガープリントも別経路で確認できるようにします。

実際に使うAction、ビルドツール、ソース依存物も製品ごとに選び、内部Forgejoへ登録または対象サーバへ搬入する計画を作ります。外部URLを参照する`uses:`、Gitサブモジュール、LFS、パッケージ取得先は、隔離LAN内で使えるものへ置き換えます。ForgejoとRunnerの基本導入に不要なActionやツールは取得しません。

対象サーバのSSHホスト鍵を照合済みの状態で、次を実行します。`StrictHostKeyChecking=yes`を外しません。転送完了後、対象サーバ側の署名・ハッシュ検証が済むまで準備端末のファイルを保持します。

```powershell
ssh -o StrictHostKeyChecking=yes "${FORGEJO_USER}@${FORGEJO_HOST}" 'mkdir -m 700 -p ~/forgejo-install'
scp -o StrictHostKeyChecking=yes "$STAGE\forgejo-15.0.10-linux-amd64" "$STAGE\forgejo-15.0.10-linux-amd64.asc" "$STAGE\forgejo-runner-13.2.0-linux-amd64" "$STAGE\forgejo-runner-13.2.0-linux-amd64.asc" "$STAGE\forgejo-release-key.asc" "$STAGE\forgejo.service" "${FORGEJO_USER}@${FORGEJO_HOST}:/home/${FORGEJO_USER}/forgejo-install/"
```

RPMをファイル搬入する場合は、RPM一式を入れた`$STAGE\rpms`ディレクトリをSCPまたは承認済み媒体で同じ場所へ転送します。転送後、[導入手順](installation.md)の第1節で`RPM_DIR`を`/home/devops/forgejo-install/rpms`へ合わせます。管理ユーザー名を変えた場合はパスも変えます。

```powershell
scp -r -o StrictHostKeyChecking=yes "$STAGE\rpms" "${FORGEJO_USER}@${FORGEJO_HOST}:/home/${FORGEJO_USER}/forgejo-install/"
```

## 5. 初期パスワードの受け取り

[導入手順の第4節](installation.md#4-初期管理者)で管理者アカウントを作成した後に、この節を実施します。初期パスワードを含むサーバ上の一時ファイルを、準備端末のGit管理外へSCPで取得します。以下はWindowsユーザー本人の`.ssh`ディレクトリへ保存する例です。転送後に保存ファイルが存在することを確認し、Windows ACLを本人だけに絞ります。秘密値を画面や作業ログに表示しません。

```powershell
$FORGEJO_HOST = 'forgejo.internal.example'  # 対象サーバの内部DNS名またはIPへ変更
$FORGEJO_USER = 'devops'                    # 対象サーバの管理ユーザーへ変更
$secretDir = Join-Path $HOME '.ssh'
New-Item -ItemType Directory -Force -Path $secretDir | Out-Null
$secretPath = Join-Path $secretDir 'forgejo-admin-initial.txt'
scp -o StrictHostKeyChecking=yes "${FORGEJO_USER}@${FORGEJO_HOST}:/home/${FORGEJO_USER}/forgejo-admin-initial.txt" "$secretPath"
Test-Path -Path $secretPath
$account = whoami
icacls $secretPath /inheritance:r /grant:r "${account}:F"
```

`Test-Path`が`True`を返し、`icacls`が成功したことを確認します。サーバ側の一時ファイルを削除するため、[導入手順の第4節](installation.md#4-初期管理者)に戻ります。初回ログイン後に管理者パスワードを変更し、ローカルに保存した初期パスワードも組織の秘密情報管理方針に従って扱います。
