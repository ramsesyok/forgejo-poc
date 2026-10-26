# C++ release sample

Oracle Linux 8 上で CMake と C++17 を使って Linux x86_64 の実行ファイルを生成する小さなサンプルです。Java サンプルとは別の Forgejo リポジトリとリリース履歴で管理します。

## 処理の順序

| 順序 | 担当 | すること |
| --- | --- | --- |
| 1 | ワークフローのビルドステップ | CMake でビルドし、CTest と実行ファイルの動作を確認する |
| 2 | `package-release.sh` | 実行ファイル・起動停止シェル・指定されたライブラリを `build/cpp-release-sample/` に集め、ZIP とチェックサムを作る |
| 3 | ワークフローの下書き作成ステップ | 手動実行時だけ、完成済みの配布ファイルを Forgejo の下書きリリースに添付する |

ワークフローはビルドとテスト、下書きリリースの作成を直接実行し、配布ファイルの梱包にはシェルを呼び出します。`start_cpp.sh` と `stop_cpp.sh` は処理を進めるシェルではなく、ZIP に入れる配布物です。`runtime-libraries.txt` はコピー対象を並べる設定ファイルです。

手元では公開せずに、ビルドと ZIP 作成まで試せます。

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DSAMPLE_VERSION=0.1.0
cmake --build build --parallel 2
(cd build && ctest --output-on-failure)
test "$(build/bin/cpp-release-sample)" = 'Hello from Forgejo Actions!'
test "$(build/bin/cpp-release-sample --version)" = 'cpp-release-sample 0.1.0'
bash scripts/package-release.sh
./build/bin/cpp-release-sample --version
./build/cpp-release-sample/start_cpp.sh
cmake -E tar tf dist/cpp-release-sample-0.1.0-linux-x86_64.zip
```

通常実行では `Hello from Forgejo Actions!`、`--version` では埋め込んだバージョンを表示します。CMake の `BUILD_TESTING` により CTest も実行します。サンプルの実行ファイルはすぐ終了するため、`stop_cpp.sh` は停止対象がないことを表示します。実プロジェクトでは両シェルを置き換えます。

## 配布フォルダ

`package-release.sh` は実行ファイル、`start_cpp.sh`、`stop_cpp.sh`、README、共有ライブラリを `build/cpp-release-sample/` に集め、このフォルダをそのまま ZIP に収めます。

```text
build/cpp-release-sample/
├── cpp-release-sample
├── start_cpp.sh
├── stop_cpp.sh
├── README.md
└── lib/
```

配布する共有ライブラリは `scripts/runtime-libraries.txt` に 1 行 1 件のパスまたは glob で指定します。例えば `/usr/local/lib/libexample.so*` です。コピーには `cp -P` を使い、シンボリックリンクを保持します。glob が 1 件も一致しない場合は失敗します。サンプルでは外部ライブラリを必要としないため、設定例はコメントアウトしています。実プロジェクトでは必要なライブラリとリンク先の実ファイルを指定し、gRPC 等のビルド設定も実装チームで調整します。

## Forgejo Actions

`.forgejo/workflows/build-release.yml` は `el8-mydev` Runner で動きます。VM の標準リポジトリから CMake、`gcc-c++`、`make` をインストールしておきます。ZIP 作成にも CMake の `-E tar --format=zip` を使います。

- `main` への push: そのコミットのソースを取得し、Release ビルドと CTest、配布フォルダへのコピー、ZIP 作成、チェックサム照合を実行します。リリースは作りません。
- 下書きリリース: Actions 画面で `build-release.yml` を `main` から実行し、`tag` に `v0.1.0` や `20261024.01` のようなタグ名を入力します。Actions が同じ検査を実行した後、下書きリリースを作り、実行ファイル、配布フォルダを収めた ZIP、`SHA256SUMS` を添付します。内容を確認してリリースノートを追記し、Forgejo の画面から手動で正式公開します。

Java WAR サンプルと同じくタグ名の形式チェックはしません。先頭の `v` があれば除いた値を CMake の `SAMPLE_VERSION` と配布ファイル名に使います。例えば `20261024.01` なら `cpp-release-sample-20261024.01-linux-x86_64.zip` です。Git のタグ名、C++ の文字列、ファイル名として使えない文字を含む場合は後続処理で失敗します。

リリース本文には元ソースの完全な 40 桁のコミット ID（SHA-1）を記録します。`SHA256SUMS` は実行ファイルと ZIP の内容を検証するための別の値です。両方を同じディレクトリに置くと `sha256sum -c SHA256SUMS` で照合できます。

外部 Action は使わず、Forgejo API と Runner 上のコマンドだけで処理します。添付が完了してもリリースは下書きのまま残し、同じバージョンのリリースは作り直しません。添付途中で Actions が失敗した場合は不完全な下書きが残るため、再実行前に内容を確認してください。
