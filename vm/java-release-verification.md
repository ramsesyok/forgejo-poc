# Java サンプルの Forgejo Actions 検証（2026-10-24）

## 構成

- Forgejo: 15.0.10、検証 VM `forgejo-lab`
- リポジトリ: 非公開の [`forgejo-admin/java-release-sample`](http://192.168.131.131:3000/forgejo-admin/java-release-sample)
- Runner: `el8-mydev:host`、実行ユーザー `mydev`
- ビルド環境: Amazon Corretto 17.0.21、Apache Maven 3.10.0。VM の `/opt/forgejo-java-tools` に配置
- サンプルの作業元: [`examples/java-release-sample`](../examples/java-release-sample/README.md)

## 確認結果

1. Spring Boot 4.1.2 の JAR を VM 上で `mvn package` により生成し、`/hello` が `Hello from Forgejo Actions!` を返すことを確認した。`-Drevision=0.1.1` によるバージョン指定ビルドも成功した。
2. Forgejo に独立したリポジトリを作成し、サンプルの `main` を登録した。初回 push の [Actions 実行](http://192.168.131.131:3000/forgejo-admin/java-release-sample/actions/runs/1)は失敗した。原因は Runner の `PrivateTmp=true` により、`/var/tmp` に置いた Maven がジョブから見えなかったこと。ビルド環境を `/opt` へ配置し、ワークフローのパスを修正した。
3. 修正後の `main` push による [Actions 実行](http://192.168.131.131:3000/forgejo-admin/java-release-sample/actions/runs/2)は成功した。対象コミットは `462817e51824a77fe45ae913222b3d3e067ef993`。
4. `main` からバージョン `v0.1.0` を指定して [リリース用ワークフロー](http://192.168.131.131:3000/forgejo-admin/java-release-sample/actions/runs/3)を起動し、成功を確認した。
5. [リリースページ](http://192.168.131.131:3000/forgejo-admin/java-release-sample/releases/tag/v0.1.0)は公開状態（下書きではない）。タグは上記コミットを指し、`java-release-sample-0.1.0.jar`（19,963,788 バイト）、`java-release-sample-0.1.0.zip`（18,112,341 バイト）、`SHA256SUMS`（192 バイト）が添付されている。Forgejo が自動生成するソース ZIP と tar.gz も表示された。

リリース本文は、完全なコミット ID `462817e51824a77fe45ae913222b3d3e067ef993` が画面でも省略されず読めるよう、インラインコードとして表示する形式に更新した。`SHA256SUMS` の値は成果物の SHA-256 であり、コミット ID ではない。

ワークフローでは外部の `uses:` Action を参照せず、Forgejo の自動トークンと API を使用した。今回の Maven 依存ライブラリは、検証 VM からインターネットへ接続して取得した。
