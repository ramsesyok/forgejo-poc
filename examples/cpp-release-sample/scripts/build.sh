#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo 'Usage: build.sh [version-without-v]' >&2
  exit 2
fi

version="${1:-0.1.0}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'Version must be MAJOR.MINOR.PATCH' >&2
  exit 2
fi

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DSAMPLE_VERSION="$version"
cmake --build build --parallel 2
(cd build && ctest --output-on-failure)

test "$(build/cpp-release-sample)" = 'Hello from Forgejo Actions!'
test "$(build/cpp-release-sample --version)" = "cpp-release-sample $version"
echo "Built and tested cpp-release-sample $version"
