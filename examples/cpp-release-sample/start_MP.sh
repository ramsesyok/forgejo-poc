#!/usr/bin/env bash
# 配布フォルダ内で実行ファイルを起動するサンプル。実プロジェクトの起動方式に置き換える。
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec "$script_dir/cpp-release-sample" "$@"
