#!/usr/bin/env bash
# CMake でビルドし、CTest と簡単な動作確認を行う。
set -euo pipefail # エラー・未定義変数・パイプ中の失敗があれば終了する。

# 引数はタグの先頭の v を除いた版番号。形式は限定しない。省略時は 0.1.0。
if [ "$#" -gt 1 ]; then
  echo 'Usage: build.sh [version-without-v]' >&2
  exit 2
fi

version="${1:-0.1.0}"

# -S はソース、-B は生成物の置き場。実行ファイルは build/bin/ に出る。
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DSAMPLE_VERSION="$version"
cmake --build build --parallel 2
# CMakeLists.txt で定義した 2 件のテストを実行する。
(cd build && ctest --output-on-failure)

# テスト設定とは別に、完成した実行ファイルの出力も確かめる。
test "$(build/bin/cpp-release-sample)" = 'Hello from Forgejo Actions!'
test "$(build/bin/cpp-release-sample --version)" = "cpp-release-sample $version"
echo "Built and tested cpp-release-sample $version"
