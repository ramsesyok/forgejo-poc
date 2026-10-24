#!/usr/bin/env bash
# package-release.sh が作ったファイルを Forgejo リリースへ登録する。
# このスクリプトだけではビルドも ZIP 作成も行わない。
set -euo pipefail # エラー・未定義変数・パイプ中の失敗があれば終了する。

# 手動実行で入力したタグをそのまま使う。必須入力だが形式は限定しない。
tag="${1:-}"
if [ -z "$tag" ]; then
  echo 'Release tag is required' >&2
  exit 2
fi

# Forgejo Actions が渡す API 情報と、一時的な認証トークンを確認する。
: "${API_TOKEN:?Missing Forgejo Actions token}"
: "${FORGEJO_API_URL:?Missing Forgejo API URL}"
: "${FORGEJO_REPOSITORY:?Missing Forgejo repository}"
: "${FORGEJO_SHA:?Missing triggering commit SHA}"

artifact="cpp-release-sample-${tag#v}-linux-x86_64"
archive="${artifact}.zip"
# 公開前に必要な 3 ファイルと SHA-256 の一致を確認する。
test -s "dist/$artifact"
test -s "dist/$archive"
test -s dist/SHA256SUMS
(cd dist && sha256sum -c SHA256SUMS)

release_url="${FORGEJO_API_URL}/repos/${FORGEJO_REPOSITORY}/releases"
# 同名タグのリリースがある場合は上書きせず停止する。
status=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  --header "Authorization: token ${API_TOKEN}" "${release_url}/tags/${tag}")
if [ "$status" != 404 ]; then
  echo "Release ${tag} must not exist (API status ${status})" >&2
  exit 1
fi

# 添付が揃うまで公開しないよう、まず下書きリリースを作成する。
# 本文にはビルド元のコミット ID を残す。
payload=$(printf '{"tag_name":"%s","target_commitish":"%s","name":"%s","body":"Full source commit ID (SHA-1): `%s`","draft":true,"prerelease":false}' \
  "$tag" "$FORGEJO_SHA" "$tag" "$FORGEJO_SHA")
response=$(curl --fail --silent --show-error --request POST \
  --header "Authorization: token ${API_TOKEN}" \
  --header 'Content-Type: application/json' \
  --data "$payload" "$release_url")
# 添付先の識別番号を Forgejo の応答から読み取る。
release_id=$(printf '%s' "$response" | perl -ne 'if (/^\{"id":\s*(\d+),/) { print "$1\n"; exit }')
if [[ ! "$release_id" =~ ^[0-9]+$ ]]; then
  echo 'Could not read release ID from Forgejo response' >&2
  exit 1
fi

# 実行ファイル、ZIP、チェックサムを下書きリリースへ添付する。
for asset in "$artifact" "$archive" SHA256SUMS; do
  curl --fail --silent --show-error --request POST \
    --header "Authorization: token ${API_TOKEN}" \
    --form "attachment=@dist/${asset}" \
    "${release_url}/${release_id}/assets?name=${asset}" > /dev/null
done

# すべての添付が成功した場合だけ公開する。
curl --fail --silent --show-error --request PATCH \
  --header "Authorization: token ${API_TOKEN}" \
  --header 'Content-Type: application/json' \
  --data '{"draft":false}' "${release_url}/${release_id}" > /dev/null

echo "Published ${tag} with executable, ZIP, and SHA256SUMS"
