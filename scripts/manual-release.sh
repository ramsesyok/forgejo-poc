#!/usr/bin/env bash
set -euo pipefail

# プロジェクトごとに、この設定と添付ファイル名を変更する。
FORGEJO_API_URL='http://192.168.131.131:3000/api/v1'
FORGEJO_REPOSITORY='myproject/java-war-release-template'
SOURCE_COMMIT=$(git rev-parse HEAD)
ASSET_DIR='dist'
ASSETS=(
  'mywebapp-0.1.0.war'
  'dbscript.tar.gz'
  'release-0.1.0.zip'
  'SHA256SUMS'
)

: "${FORGEJO_TOKEN:?FORGEJO_TOKEN を環境変数に設定してください}"
[[ $SOURCE_COMMIT =~ ^[0-9a-fA-F]{40}$ ]] || { echo 'Git リポジトリ内で実行してください' >&2; exit 1; }
for asset in "${ASSETS[@]}"; do
  test -s "$ASSET_DIR/$asset" || { echo "添付ファイルがありません: $ASSET_DIR/$asset" >&2; exit 1; }
done
read -r -p 'リリースタグを入力してください (例: v0.1.0): ' RELEASE_TAG || { echo 'リリースタグを入力できませんでした' >&2; exit 1; }
[[ $RELEASE_TAG =~ ^[A-Za-z0-9._-]+$ ]] || { echo 'リリースタグが空、または使えない文字があります' >&2; exit 1; }

release_url="${FORGEJO_API_URL}/repos/${FORGEJO_REPOSITORY}/releases"
status=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  --header "Authorization: token ${FORGEJO_TOKEN}" "$release_url/tags/$RELEASE_TAG")
if [[ $status != 404 ]]; then
  echo "既存リリース、または API エラーです (HTTP $status): $RELEASE_TAG" >&2
  exit 1
fi

# 元の WAR ワークフローと同じく、まず下書きとして作成する。
revision=${RELEASE_TAG#v}
payload=$(printf '{"tag_name":"%s","target_commitish":"%s","name":"%s","body":"Source commit: %s\\nMaven revision: %s","draft":true,"prerelease":false}' \
  "$RELEASE_TAG" "$SOURCE_COMMIT" "$RELEASE_TAG" "$SOURCE_COMMIT" "$revision")
response=$(curl --fail --silent --show-error --request POST \
  --header "Authorization: token ${FORGEJO_TOKEN}" \
  --header 'Content-Type: application/json' \
  --data "$payload" "$release_url")
release_id=$(printf '%s' "$response" | perl -ne 'if (/^\{"id":\s*(\d+),/) { print "$1\n"; exit }')
[[ $release_id =~ ^[0-9]+$ ]] || { echo 'リリース ID を取得できませんでした' >&2; exit 1; }

for asset in "${ASSETS[@]}"; do
  curl --fail --silent --show-error --request POST \
    --header "Authorization: token ${FORGEJO_TOKEN}" \
    --form "attachment=@${ASSET_DIR}/${asset}" \
    "$release_url/$release_id/assets?name=$asset" > /dev/null
  echo "添付しました: $asset"
done
echo "下書きリリースを確認してください: $RELEASE_TAG (ID: $release_id)"
