#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo 'Usage: build.sh [version-without-v]' >&2
  exit 2
fi

if [ "$#" -eq 1 ]; then
  mvn -B -ntp -Drevision="$1" clean package
  jar_path="target/java-release-sample-$1.jar"
else
  mvn -B -ntp clean package
  jar_path='target/java-release-sample-0.1.0.jar'
fi

test -s "$jar_path"

port=18080
java -jar "$jar_path" --server.address=127.0.0.1 --server.port="$port" > target/smoke.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT

for attempt in $(seq 1 40); do
  response=$(curl --silent --fail --max-time 2 "http://127.0.0.1:${port}/hello") && break
  sleep 1
done

if [ "${response:-}" != 'Hello from Forgejo Actions!' ]; then
  cat target/smoke.log >&2
  echo 'HTTP smoke test failed' >&2
  exit 1
fi

echo "Built and tested $jar_path"
