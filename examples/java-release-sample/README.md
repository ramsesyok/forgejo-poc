# Java release sample

JDK 17 と Spring Boot 4.1.2 の小さな Web アプリです。Forgejo Actions で `main` をビルドし、リリースページへ実行可能 JAR と ZIP を登録する例として使います。

```bash
mvn -B clean package
java -jar target/java-release-sample-0.1.0.jar
curl http://localhost:8080/hello
```

`/hello` は `Hello from Forgejo Actions!` を返します。

## Forgejo Actions

`.forgejo/workflows/build-release.yml` は `el8-mydev` Runner で実行します。この検証 VM では JDK と Maven を `/opt/forgejo-java-tools` に配置しています。別の Runner へ移す場合はワークフローの `JAVA_HOME` と `MAVEN_HOME` を合わせます。

- `main` への push: そのコミットのソースを取得し、JAR をビルドして `/hello` の応答を検査します。
- リリース: Actions 画面で `build-release.yml` を `main` から実行し、`v0.1.0` のようなバージョンを入力します。ビルドと検査の後、Actions がタグ・リリースページを作り、実行可能 JAR、JAR と README をまとめた ZIP、`SHA256SUMS` を添付します。

リリース本文には、ビルド元の完全な40桁のコミット ID（SHA-1）を記録します。`SHA256SUMS` には JAR と ZIP のファイルハッシュを記録し、コミット ID とは区別します。

外部 Action は利用せず、Forgejo API と Runner 上のコマンドだけで処理します。リリースは添付が完了するまで下書きにします。同じバージョンのリリースは作り直しません。

Forgejo 上のタグがリリース時点のソースコードを固定します。リリースページからソースの ZIP・tar.gz も取得できます。
