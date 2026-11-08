# 手動で用意したファイルのリリース登録

Actions を使わずに、作成済みのファイルを Forgejo の**下書きリリース**へ登録する例です。[`scripts/manual-release.sh`](scripts/manual-release.sh) は、Java WAR ワークフローのリリース作成・添付部分を抜き出したものです。Bash、`curl`、Perl を使用します。

## プロジェクトごとの変更箇所

スクリプト冒頭の `FORGEJO_API_URL`、`FORGEJO_REPOSITORY`、`ASSET_DIR`、`ASSETS` を手動で変更してください。リリースタグは実行時のプロンプトで入力し、`ASSETS` のバージョン付きファイル名もそのタグに合わせてください。`SOURCE_COMMIT` は実行場所の `git rev-parse HEAD` から取得します。`ASSET_DIR` は実行時のカレントディレクトリからの相対パスです。サンプルでは WAR、DDL アーカイブ、ZIP、`SHA256SUMS` の4件を登録します。

ビルドに使ったクローンのルートディレクトリから実行してください。事前に `git status --short` で未コミットの変更がないこと、対象コミットが Forgejo に登録済みであること、配布ファイルの内容とチェックサムを確認します。`SHA256SUMS` を使う場合は、例えば配布ディレクトリで `sha256sum -c SHA256SUMS` を実行します。

```bash
read -rsp 'Forgejo token: ' FORGEJO_TOKEN
echo
export FORGEJO_TOKEN
bash scripts/manual-release.sh
unset FORGEJO_TOKEN
```

トークンには対象リポジトリへの書き込み権限が必要です。スクリプトは同じタグのリリースが既にあれば停止し、ファイルを確認してから下書きを作成・添付します。添付後は Forgejo の画面で内容を確認して公開してください。途中で失敗した場合は下書きが残るため、画面で状態を確認してから対処します。

検証 VM の HTTP URL ではトークンが暗号化されません。実運用では HTTPS の URL に変更してください。
