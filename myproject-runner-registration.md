# `myproject` の作成と組織 Runner の登録

Forgejo に組織 `myproject` を作成し、組織内のリポジトリで利用できる Runner を登録する手順です。**リポジトリの作成前に実施できます。** 対象は[導入手順](installation.md)どおりに稼働中の Forgejo 15.0 / Runner 13.2 検証 VM です。新規 VM の初期導入ではなく、既存 VM に組織向けの接続を追加します。

この手順では、稼働中の `forgejo-runner-mydev.service` に `myproject` 用の接続を追加します。既存の `forgejo-admin` ユーザー単位の接続は残します。ジョブはどちらの接続から受けても `mydev` ユーザーでホスト上に実行され、Runner のラベルは既存の `el8-mydev:host` を共有します。組織のリポジトリにワークフローを書ける人がこの環境でジョブを実行できるため、`myproject` のメンバーとリポジトリの書き込み権限を先に決めてください。

確認用の行は1行ずつ実行し、`OK`を見てから次へ進みます。`NG`が出たら作業を止めて原因を確認します。

## 1. 現在の Runner を確認する

対象 VM でサービスが稼働していることを確認します。以降のサーバ操作には管理ユーザーの `sudo` 権限が必要です。

```bash
systemctl is-active forgejo forgejo-runner-mydev
```

現在の設定ファイルは `/home/mydev/runner-config.yml`、Runner の実行ユーザーは `mydev` です。既存の `server.connections.local` と `runner.labels` は変更しません。

## 2. Forgejo の画面で組織を作成する

1. `forgejo-admin` で Forgejo にログインします。
2. 画面右上の `+` から **新しい組織 / New Organization** を開きます。
3. 組織名に `myproject` を入力し、公開範囲などの項目を運用方針に合わせて選び、**組織を作成 / Create Organization** を押します。
4. 組織ページの URL が `<Forgejo の URL>/myproject` であることを確認します。既に `myproject` が存在し、`forgejo-admin` が組織管理者なら、この作成操作は不要です。

## 3. 組織の画面で Runner を登録する

1. `myproject` の **設定 → Actions → Runners** を開きます。組織の管理権限で操作します。
2. **Create new runner** を押し、識別しやすい名前（例: `myproject-mydev`）と説明を入力して作成します。
3. 表示された **UUID** と **Token** を、この後の Runner 設定に使います。UUID は`runner-config.yml`の`uuid`、Token は`runner-token-myproject`の内容です。Token は秘密情報として扱い、手順書や Git に記載しません。両者を取り違えないよう、画面を閉じる前に次の手順へ進みます。

組織単位の Runner は、その組織が所有するリポジトリを対象にします。組織 Runner の作成場所、UUID・Token の表示、複数接続の設定方法は[Forgejo 15.0 の Runner 登録手順](https://forgejo.org/docs/v15.0/admin/actions/registration/)を参照してください。

## 4. Token を VM のファイルへ保存する

対象 VM の対話端末で root シェルに入り、画面で表示された Token を入力します。`read -s` は入力を端末に表示せず、`printf` はファイル末尾に改行を追加しません。Token をコマンド文字列に直接書き込まないため、シェル履歴にも残りません。

```bash
sudo -i
umask 077
read -r -s -p 'myproject Runner Token: ' MYPROJECT_RUNNER_TOKEN
printf '\n'
printf '%s' "$MYPROJECT_RUNNER_TOKEN" > /home/mydev/runner-token-myproject
unset MYPROJECT_RUNNER_TOKEN
chown mydev:mydev /home/mydev/runner-token-myproject
chmod 0600 /home/mydev/runner-token-myproject
if test -s /home/mydev/runner-token-myproject; then echo 'OK: 組織Runner Tokenを保存'; else echo 'NG: 組織Runner Tokenがないか空です' >&2; false; fi
```

## 5. Runner 設定へ組織用の接続を追加する

設定ファイルを複製してから `vi /home/mydev/runner-config.yml` で編集します。既存の `server.connections.local` の**同じ階層**に、次の `myproject` ブロックを追加します。`uuid` は画面に表示された値へ置き換えます。`server.connections.local` の UUID と Token は変更しません。

```bash
cp -p /home/mydev/runner-config.yml /home/mydev/runner-config.yml.before-myproject
vi /home/mydev/runner-config.yml
```

```yaml
server:
  connections:
    # 既存の local: ブロックはそのまま残す
    myproject:
      url: http://127.0.0.1:3000/
      uuid: <myproject の画面に表示された UUID>
      token_url: file:/home/mydev/runner-token-myproject
```

この YAML は追加位置を示す抜粋です。ファイル全体をこの内容で置き換えないでください。`url` は Runner と Forgejo を同じ VM で動かす現在の構成に合わせています。

```bash
chown mydev:mydev /home/mydev/runner-config.yml
chmod 0600 /home/mydev/runner-config.yml
if awk '/^    myproject:/ { found=1; next } found && /^    [^ ]/ { exit } found && /^      uuid:/ { print $2; exit }' /home/mydev/runner-config.yml | grep -Eq '^([[:xdigit:]]{32}|[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12})$'; then echo 'OK: myprojectのUUID形式'; else echo 'NG: myprojectのUUID形式が違います' >&2; false; fi
```

最後の確認で`NG`が出た場合は、`myproject`接続の`uuid`を画面に表示されたUUIDへ直してから再実行します。既存の`local`接続のUUIDは変更しません。`OK`を確認したらサービスを再起動します。

```bash
systemctl restart forgejo-runner-mydev
systemctl is-active forgejo-runner-mydev
journalctl -u forgejo-runner-mydev -n 30 --no-pager
exit
```

## 6. 登録結果を確認する

1. Forgejo の `myproject` **設定 → Actions → Runners** で、`myproject-mydev` がオンラインで、ラベル `el8-mydev` を持つことを確認します。この時点でリポジトリはなくても構いません。
2. 後から `myproject` にリポジトリを作成または移管したら、そのリポジトリの **設定 → Actions → Runners** に組織 Runner が表示されることを確認します。

次は[リリース用リポジトリとワークフローの導入](forgejo-workflow.md)へ進みます。

組織 Runner がオフラインなら、Runner サービスのログ、追加した UUID、Token ファイルの所有者・権限、`server.connections` の YAML インデントを確認します。リポジトリでジョブが待機したままなら、そのリポジトリから Runner が見えるか、`runs-on` とラベルが一致するかを確認します。
