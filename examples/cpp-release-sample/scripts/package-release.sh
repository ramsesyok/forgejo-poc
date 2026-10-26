#!/usr/bin/env bash
# ビルド済み実行ファイルと配布用ファイルを集め、ZIP とチェックサムを作る。
# 単独で試す場合は、先に CMake でビルドする。
set -euo pipefail # エラー・未定義変数・パイプ中の失敗があれば終了する。

# 手動リリース時は v を除いた版番号を渡す。形式は限定しない。
# push 時はサンプル既定値を使う。
if [ "$#" -gt 1 ]; then
  echo 'Usage: package-release.sh [version-without-v]' >&2
  exit 2
fi
version="${1:-0.1.0}"

if [ "$(uname -m)" != x86_64 ]; then
  echo 'This sample packages Linux x86_64 binaries only' >&2
  exit 1
fi

name=cpp-release-sample
binary="build/bin/$name"
stage="build/$name"
library_list="${RUNTIME_LIBRARIES_FILE:-scripts/runtime-libraries.txt}"
artifact="${name}-${version}-linux-x86_64"
archive="${artifact}.zip"

# 1. ビルド結果と配布用ファイルが揃っているか確認する。
if [ ! -x "$binary" ]; then
  echo "Missing build output: $binary (run cmake build first)" >&2
  exit 1
fi
for required in "$library_list" README.md start_cpp.sh stop_cpp.sh; do
  if [ ! -f "$required" ]; then
    echo "Missing release input: $required" >&2
    exit 1
  fi
done

# 2. 前回の配布フォルダを作り直し、実行ファイルと起動・停止シェルを集める。
rm -rf -- "$stage"
mkdir -p "$stage/lib"
cp -- "$binary" README.md "$stage/"
cp -P -- start_cpp.sh stop_cpp.sh "$stage/"
chmod +x "$stage/start_cpp.sh" "$stage/stop_cpp.sh"

# 3. 設定ファイルの各行を展開し、必要な共有ライブラリを lib/ にコピーする。
#    compgen -G は *.so* のようなワイルドカードを実際のファイル名に展開する。
library_count=0
while IFS= read -r pattern || [[ -n "$pattern" ]]; do
  if [[ -z "$pattern" || "$pattern" =~ ^[[:space:]]*# ]]; then
    continue
  fi
  mapfile -t matches < <(compgen -G "$pattern" || true)
  if ((${#matches[@]} == 0)); then
    echo "No library matched: $pattern" >&2
    exit 1
  fi
  for source in "${matches[@]}"; do
    if [[ ! -f "$source" && ! -L "$source" ]]; then
      echo "Not a library file: $source" >&2
      exit 1
    fi
    cp -P -- "$source" "$stage/lib/" # -P は .so のシンボリックリンクを保持する。
    ((library_count += 1))
  done
done < "$library_list"

actual_version=$("$stage/$name" --version)
if [ "$actual_version" != "$name $version" ]; then
  echo "Built version does not match release version: $actual_version" >&2
  exit 1
fi

# 4. build/<name>/ を ZIP のルートに含める。単独の実行ファイルも添付用に置く。
mkdir -p dist
cp -- "$stage/$name" "dist/$artifact"
(
  cd build
  cmake -E tar cf "../dist/$archive" --format=zip "$name"
)

# 5. ダウンロード後に破損を確認できるよう SHA-256 を記録し、ここでも照合する。
(
  cd dist
  sha256sum "$artifact" "$archive" > SHA256SUMS
  sha256sum -c SHA256SUMS
)

echo "Packaged dist/$archive with $library_count runtime libraries"
