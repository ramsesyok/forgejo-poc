# C++ release sample

Oracle Linux 8 上で CMake と C++17 を使って Linux x86_64 の実行ファイルを生成する小さなサンプルです。Java サンプルとは別の Forgejo リポジトリとリリース履歴で管理します。

```bash
bash scripts/build.sh
./build/cpp-release-sample
./build/cpp-release-sample --version
```

通常実行では `Hello from Forgejo Actions!`、`--version` では埋め込んだバージョンを表示します。CMake の `BUILD_TESTING` により CTest も実行します。

## Forgejo Actions

`.forgejo/workflows/build-release.yml` は `el8-mydev` Runner で動きます。VM の標準リポジトリから CMake、`gcc-c++`、`make` をインストールしておきます。

- `main` への push: そのコミットのソースを取得し、Release ビルドと CTest を実行します。
- リリース: Actions 画面で `build-release.yml` を `main` から実行し、`v0.1.0` のようなバージョンを入力します。Actions がビルド・テスト後、タグとリリースページを作り、実行ファイル、実行ファイルと README を含む tar.gz、`SHA256SUMS` を添付します。

リリース本文には元ソースの完全な40桁のコミット ID（SHA-1）を記録します。`SHA256SUMS` は実行ファイルと tar.gz の内容を検証するための別の値です。両方を同じディレクトリに置くと `sha256sum -c SHA256SUMS` で照合できます。

外部 Action は使わず、Forgejo API と Runner 上のコマンドだけで処理します。添付が完了するまではリリースを下書きにし、同じバージョンのリリースは作り直しません。
