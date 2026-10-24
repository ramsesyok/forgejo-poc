# Java・C++ リリースワークフローの利用準備

この文書は、[Java WAR サンプル](examples/java-war-release-template/README.md)と[C++ サンプル](examples/cpp-release-sample/README.md)を Forgejo の独立したリポジトリで動かすための設定をまとめたものです。対象はこのリポジトリの[導入手順](installation.md)で構築した Forgejo 15.0 と Forgejo Runner 13.2 の環境です。

## 1. ワークフローをリポジトリに配置する

各サンプルの**フォルダの中身**を、それぞれの Forgejo リポジトリのルートへ配置して `main` に push します。配置後のワークフローのパスは `.forgejo/workflows/build-release.yml` です。`examples/<サンプル名>/` の階層は含めません。[Forgejo Actions クイックスタート](https://forgejo.org/docs/v15.0/user/actions/quick-start/)

両ワークフローの起動条件は次のとおりです。

| 操作 | 実行内容 |
| --- | --- |
| `main` へ push | ビルド・テスト・梱包を実行する。リリースは作成しない |
| Actions 画面から `main` を選び、`tag` を入力して手動実行 | ビルド・テスト・梱包後、タグと Forgejo リリースを作成する |

タグを push するだけでは手動リリースは始まりません。手動実行には `workflow_dispatch` を使用します。[Forgejo Actions のイベント仕様](https://forgejo.org/docs/v15.0/user/actions/reference/)

## 2. Forgejo 側で確認する設定

| 場所 | 確認・設定すること |
| --- | --- |
| Forgejo 管理設定 | `[actions] ENABLED = true`。この環境の `app.ini` では有効化済み。Actions がリポジトリ設定に表示されない場合は、管理者がインスタンス設定を確認する |
| 各リポジトリの **設定 → Units → Overview** | **Actions** にチェックが入っていることを確認する。無効なら有効化する |
| 各リポジトリの **設定 → Actions → Runners** | オンラインの Runner が表示され、ワークフローの `runs-on: el8-mydev` と一致するラベルを持つことを確認する |

この環境の Runner は `forgejo-admin` **ユーザー単位**で登録され、ラベルは `el8-mydev:host` です。`forgejo-admin` が所有する新しいリポジトリなら、リポジトリごとの Runner 登録は不要です。

組織を作成したり、リポジトリを組織へ移したりしても、この登録範囲は自動では変わりません。組織所有のリポジトリで実行するには、組織の **設定 → Actions → Runners** で組織単位の Runner を登録します。既存の Runner プロセスに組織向けの接続を追加することもできますが、その場合も組織用の登録が別途必要です。登録後は、対象リポジトリの Runner 一覧で利用可能か確認し、`runs-on` をラベルに合わせます。[`myproject` の作成と登録手順](myproject-runner-registration.md)、[Forgejo Runner の登録範囲と複数接続](https://forgejo.org/docs/v15.0/admin/actions/registration/)

ワークフローは実行時に自動発行される `${{ forgejo.token }}` を Forgejo API へのアクセスに使います。このサンプルを現在の環境で動かすために、個人アクセストークンやリポジトリ Secret、Webhook を追加登録する必要はありません。[Forgejo のトークン仕様](https://forgejo.org/docs/v15.0/user/actions/reference/)

## 3. Runner 上のビルド環境

Runner のサービスは `mydev` ユーザーで動き、ジョブはホスト上で実行されます。両ワークフローは Forgejo API から対象コミットのアーカイブを取得するため、Runner から Forgejo の API URL に接続でき、`bash`、`curl`、`tar`、`sha256sum` を実行できる必要があります。外部の `uses:` Action は利用しません。

| サンプル | Runner に必要なもの | ワークフローで合わせる値 |
| --- | --- | --- |
| Java WAR | JDK 17、Maven、ビルドに必要な Maven 依存物 | `JAVA_HOME=/opt/forgejo-java-tools/jdk`、`MAVEN_HOME=/opt/forgejo-java-tools/maven`、`WAR_BASENAME`、`DEFAULT_REVISION` |
| C++ | CMake、C++ コンパイラ、`make`、実プロジェクトで配布する共有ライブラリ | `runs-on`、`scripts/runtime-libraries.txt` に書いたライブラリのパス |

ネットワークを遮断した環境で Java をビルドする場合は、Maven の依存物を Runner が参照できるローカルキャッシュまたは内部リポジトリに用意します。Java の実プロジェクトでは、`pom.xml` の `revision` 指定、WAR の出力名、起動後の HTTP 検査先も合わせます。C++ サンプルでは共有ライブラリの指定はコメントアウトされています。実プロジェクトでは `runtime-libraries.txt` に指定したファイルが Runner 上にあり、`start_MP.sh` と `stop_MP.sh` が配布できる状態であることを確認します。

## 4. 動作確認

1. 対象リポジトリの `main` にワークフローを含むコミットを push し、**Actions** に実行が表示されて成功することを確認します。
2. リリースを試す場合は、**Actions** から対象のワークフローを `main` で手動実行し、`tag` を入力します。
3. 実行が成功したら、**Releases** でタグ、ZIP、個別ファイル、`SHA256SUMS` を確認します。

ワークフローが表示されなければ配置パスと Actions の有効化を、実行待ちのままなら Runner のオンライン状態とラベルを確認します。ジョブが始まってから失敗した場合は、その実行ログで API 接続、ツールのパス、ビルド依存物、配布対象ファイルを確認します。[Forgejo Actions クイックスタート](https://forgejo.org/docs/v15.0/user/actions/quick-start/)
