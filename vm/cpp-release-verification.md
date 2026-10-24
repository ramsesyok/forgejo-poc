# C++ サンプルの Forgejo Actions 検証（2026-10-24）

この文書は初期版の検証記録です。当時の配布形式は tar.gz でした。現在の C++ サンプルは配布フォルダを ZIP にまとめるため、運用手順と内容物は[現在の README](../examples/cpp-release-sample/README.md)を参照してください。

## 構成

- Forgejo: 15.0.10、Oracle Linux Server 8.10 の検証 VM `forgejo-lab`
- 非公開リポジトリ: [`forgejo-admin/cpp-release-sample`](http://192.168.131.131:3000/forgejo-admin/cpp-release-sample)
- Runner: `el8-mydev:host`、実行ユーザー `mydev`
- ローカルのサンプル: [`examples/cpp-release-sample`](../examples/cpp-release-sample/README.md)

## VM のビルド環境

Oracle Linux 8 の標準リポジトリから次を導入した。

```bash
sudo dnf install -y cmake gcc-c++ make
```

導入後の RPM は `cmake-3.26.5-2.el8.x86_64`、`gcc-c++-8.5.0-28.0.1.el8_10.x86_64`、`make-4.2.1-11.el8.x86_64`。`cmake`、`g++`、`make`、`ctest` は `/usr/bin` から利用できる。導入時には依存パッケージ22個が追加され、`libgcc`、`libgomp`、`libstdc++` が更新された。Forgejo と Runner は `active`、SELinux は `Enforcing` のまま。

## ビルドとリリース

1. VM 上でソースを直接 `bash scripts/build.sh` によりビルドした。GCC 8.5.0 で C++17 の実行ファイルを生成し、CTest の2件とコマンド出力の検査が成功した。
2. C++ 専用リポジトリの `main` へコミット `5d21df28f3153b9e7501199445e172bb4ff477ef` を push した。[push 時の Actions 実行](http://192.168.131.131:3000/forgejo-admin/cpp-release-sample/actions/runs/1)は `success`。
3. `main` から `v0.1.0` を指定して [リリース用 Actions 実行](http://192.168.131.131:3000/forgejo-admin/cpp-release-sample/actions/runs/2)を起動し、`success` を確認した。
4. [v0.1.0 リリースページ](http://192.168.131.131:3000/forgejo-admin/cpp-release-sample/releases/tag/v0.1.0)は公開状態。タグと本文は上記の完全なコミット ID を示す。添付ファイルは Linux x86_64 実行ファイル（18,792 バイト）、実行ファイルと README を含む tar.gz（5,123 バイト）、`SHA256SUMS`（215 バイト）。
5. 添付ファイルを Forgejo から取得して SHA-256 を再計算し、`SHA256SUMS` の2行と一致することを確認した。配布された実行ファイルを同 VM で起動すると `Hello from Forgejo Actions!`、`--version` で `cpp-release-sample 0.1.0` を表示した。

配布実行ファイルは Linux x86_64 の動的リンク ELF。動作検証の対象は Oracle Linux 8.10 であり、他の OS やアーキテクチャ向けのバイナリは生成していない。
