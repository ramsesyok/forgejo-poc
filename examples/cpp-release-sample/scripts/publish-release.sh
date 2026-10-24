#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'Version must be vMAJOR.MINOR.PATCH' >&2
  exit 2
fi

: "${API_TOKEN:?Missing Forgejo Actions token}"
: "${FORGEJO_API_URL:?Missing Forgejo API URL}"
: "${FORGEJO_REPOSITORY:?Missing Forgejo repository}"
: "${FORGEJO_SHA:?Missing triggering commit SHA}"

test "$(uname -m)" = x86_64
test -x build/cpp-release-sample
test "$(build/cpp-release-sample --version)" = "cpp-release-sample ${version#v}"

artifact="cpp-release-sample-${version#v}-linux-x86_64"
archive="${artifact}.tar.gz"
mkdir -p dist
cp build/cpp-release-sample "dist/$artifact"
cp README.md dist/README.md
tar -czf "dist/$archive" -C dist "$artifact" README.md
(
  cd dist
  sha256sum "$artifact" "$archive" > SHA256SUMS
)

release_url="${FORGEJO_API_URL}/repos/${FORGEJO_REPOSITORY}/releases"
status=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  --header "Authorization: token ${API_TOKEN}" "${release_url}/tags/${version}")
if [ "$status" != 404 ]; then
  echo "Release ${version} must not exist (API status ${status})" >&2
  exit 1
fi

payload=$(printf '{"tag_name":"%s","target_commitish":"%s","name":"%s","body":"Full source commit ID (SHA-1): `%s`","draft":true,"prerelease":false}' \
  "$version" "$FORGEJO_SHA" "$version" "$FORGEJO_SHA")
response=$(curl --fail --silent --show-error --request POST \
  --header "Authorization: token ${API_TOKEN}" \
  --header 'Content-Type: application/json' \
  --data "$payload" "$release_url")
release_id=$(printf '%s' "$response" | perl -ne 'if (/^\{"id":\s*(\d+),/) { print "$1\n"; exit }')
if [[ ! "$release_id" =~ ^[0-9]+$ ]]; then
  echo 'Could not read release ID from Forgejo response' >&2
  exit 1
fi

for asset in "$artifact" "$archive" SHA256SUMS; do
  curl --fail --silent --show-error --request POST \
    --header "Authorization: token ${API_TOKEN}" \
    --form "attachment=@dist/${asset}" \
    "${release_url}/${release_id}/assets?name=${asset}" > /dev/null
done

curl --fail --silent --show-error --request PATCH \
  --header "Authorization: token ${API_TOKEN}" \
  --header 'Content-Type: application/json' \
  --data '{"draft":false}' "${release_url}/${release_id}" > /dev/null

echo "Published ${version} with executable, tar.gz, and SHA256SUMS"
