# Java WAR + DDL リリースサンプル兼テンプレート

Spring Boot 4.1.2、JDK 17 の小さな WAR アプリです。`/hello` を返すソースとテスト、梱包対象と除外対象を含むサンプル DDL を置いています。`.forgejo/workflows/build-release.yml` がビルド、DDL の梱包、ZIP 作成、Forgejo リリースへの添付まで実行します。Forgejo Actions で試す場合は、このフォルダの内容を独立したリポジトリのルートに配置します。

```bash
mvn -B -ntp clean package
java -jar target/planning-api-0.1.0.war --server.port=18081
```

起動したまま別の端末で `curl http://127.0.0.1:18081/hello` を実行します。`/hello` は `Hello from WAR release sample!` を返します。`tools/DB/DDL/schema.sql` は配布例であり、アプリはデータベースに接続しません。`USER/` と `sample_devenv.sh` は除外処理を確認するためのサンプルです。

## 移植時に合わせる値

1. ワークフローの `runs-on`、`JAVA_HOME`、`MAVEN_HOME` を Runner に合わせます。
2. サンプルの `pom.xml` と `src/` を実プロジェクトのものに置き換え、`WAR_BASENAME: planning-api` と `DEFAULT_REVISION: 0.1.0` を合わせます。ワークフローは `target/${WAR_BASENAME}-${revision}.war` を想定しています。Maven の `finalName` が違う場合はワークフロー内の WAR パスを変更します。
3. 実プロジェクトの `pom.xml` が `-Drevision=...` を受け取り、WAR を生成することを確認します。
4. サンプルの `tools/DB/DDL` を実際の DDL に置き換えます。ワークフローはその内容を `dbscript/DDL` として tar.gz に収め、直下の `USER` と `*_devenv.sh` を除外します。元の DDL は変更しません。
5. `/hello` と応答文はサンプル用です。実際の WAR が別の URL やコンテナへの配備を要する場合は、HTTP 疎通検査を調整します。

## 実行

- `main` への push: 対象コミットのソースを Forgejo API から取得し、`DEFAULT_REVISION` で `mvn clean package` を実行します。Maven テストと、実行可能 WAR の `/hello` 応答を確認します。リリースは作りません。
- 手動リリース: Actions でこのワークフローを `main` から実行し、`tag` にタグ名を入力します。ワークフローではタグ名の形式を検査しません。先頭の `v` があれば除いた値を Maven の `revision` に渡してビルドします。例えば `v0.1.0` では `planning-api-0.1.0.war`、`dbscript.tar.gz`、両方を収めた `release-0.1.0.zip`、3ファイルの SHA-256 を記録した `SHA256SUMS` を Forgejo リリースへ添付します。添付が終わるまでは下書きです。同じタグ名のリリースは作り直しません。Forgejo のリリース画面で先にリリースを作る操作は、このワークフローの起動方法ではありません。

## 写真のリリースシェルとの差

| 項目 | 写真のシェル | このテンプレート |
| --- | --- | --- |
| ビルド | `mvn clean` の後に `mvn package -DskipTests -Drevision=...` | `mvn -Drevision=... clean package`。`clean` と `package` を一度の Maven 実行で行い、テストも実行 |
| Maven revision | `2.0.<短いコミット ID>-SNAPSHOT` | 入力した `v0.1.0` や `20261024.01` から先頭の `v` を除いた値 |
| WAR と DDL | 日時付きのローカルフォルダへ配置 | 2ファイルを ZIP にまとめ、個別ファイルと `SHA256SUMS` も Forgejo リリースに添付 |
| DDL の除外 | `DDL/USER` と `DDL/*_devenv.sh` | 同じ対象を一時領域の複製から除外 |
| タグ | 写真ではタグ操作がコメントアウト | 手動リリース時に Forgejo API が入力されたタグを作成。形式チェックはしない |

既存の JAR サンプルと同様に HTTP 疎通検査を行います。ZIP の内容は WAR と `dbscript.tar.gz` です。

## 検証結果

2026-10-24 に検証 VM 上の Maven 3.10.0 と JDK 17 で `mvn clean package` を実行し、テスト 1 件の成功と `planning-api-0.1.0.war` の生成を確認しました。さらに Forgejo Actions の手動実行で `20261024.01` リリースを公開しました。WAR の `/hello` 応答、ZIP 内の WAR と `dbscript.tar.gz`、DDL アーカイブからの `USER/` と `*_devenv.sh` の除外、配布ファイル 3 件の `SHA256SUMS` 照合を確認しました。
