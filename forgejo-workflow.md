# `myproject` のリリース用リポジトリとワークフロー

この文書は、`myproject` 組織が所有する Java・C++ のリリース用リポジトリに Forgejo Actions を導入する手順です。先に[組織と Runner の登録](myproject-runner-registration.md)を終え、組織 Runner がオンラインであることを確認します。Forgejo 本体の導入は[installation.md](installation.md)を参照してください。

## 1. 組織内にリポジトリを用意する

通常は、組織 `myproject` に Java と C++ のリポジトリをそれぞれ新規作成します。リポジトリ名と公開範囲を実プロジェクトに合わせ、所有者が `myproject` であることを確認します。第3節でビルド対象のソースとワークフローを `main` ブランチへ登録します。

### 既存の GitLab などから移行する場合

既存のソースと Git の履歴を引き継ぐ場合は、Forgejo の移行機能を使えます。ただし、**現在の検証 VM では** `[repository] DISABLE_MIGRATIONS = true` のため、移行画面を利用できません。次の順序で準備します。

1. Forgejo サーバから移行元 GitLab へ到達できることを確認します。非公開リポジトリや Issue などの情報も移す場合は、移行元で必要な権限を持つアクセストークンを用意します。
2. 管理者が `/etc/forgejo/app.ini` の該当値を次のように一時変更し、Forgejo を再起動します。`ALLOWED_DOMAINS` の山括弧付き部分は実際の GitLab ホスト名へ置き換えます。プライベート IP アドレスへ直接接続する場合は、`[migrations] ALLOW_LOCALNETWORKS` の設定も確認します。[Forgejo 15.0 の設定一覧](https://forgejo.org/docs/v15.0/admin/config-cheat-sheet/)

   ```ini
   [repository]
   DISABLE_MIGRATIONS = false

   [migrations]
   ALLOWED_DOMAINS = <移行元 GitLab のホスト名>
   ```

3. Forgejo の **画面右上の `+` → New Migration** から移行元として **GitLab** を選択します。GitLab 以外も、画面に表示される移行元から選択できます。移行元のリポジトリ URL と認証情報を入力し、移行先の所有者を `myproject`、リポジトリ名と公開範囲を実プロジェクトに合わせます。必要な移行項目を選び、単発の移行では継続同期用のミラーを選択しません。[Forgejo 15.0 のリポジトリ移行手順](https://forgejo.org/docs/v15.0/user/getting-started/first-repository/)
4. 移行後は所有者、ブランチ、タグ、必要な移行項目を確認します。全リポジトリの移行が終わったら、移行用の設定を元に戻して Forgejo を再起動します。

移行先では既存のソースとビルド定義を使い、第3節のワークフローを追加します。GitLab の CI 定義は Forgejo Actions のワークフローへ自動変換されません。移行元の既定ブランチが `main` 以外の場合は、ワークフロー内の対象ブランチを合わせるか、Forgejo 側の既定ブランチを `main` に変更してから第5節の手順へ進みます。

Forgejo 内の既存リポジトリを組織へ移管する場合も、移管後の所有者を確認します。

検証に使った `forgejo-admin` 所有のサンプルリポジトリと、組織が所有するリリース用リポジトリは別に扱います。ユーザー単位の Runner 登録は組織リポジトリへ自動では引き継がれません。[Runner の登録範囲](https://forgejo.org/docs/v15.0/admin/actions/registration/)

## 2. Actions と Runner を確認する

| 場所 | 確認すること |
| --- | --- |
| Forgejo 管理設定 | `[actions] ENABLED = true`。現在の検証 VM では有効化済み |
| 各リポジトリの **設定 → Units → Overview** | **Actions** にチェックが入っていること。無効なら有効にする |
| 各リポジトリの **設定 → Actions → Runners** | `myproject` の Runner がオンラインで、`el8-mydev` ラベルを持つこと |

組織 Runner が一覧にない場合は、[組織と Runner の登録手順](myproject-runner-registration.md)で登録範囲と接続状態を確認します。[Forgejo Actions クイックスタート](https://forgejo.org/docs/v15.0/user/actions/quick-start/)

## 3. ワークフローを配置する

サンプルをそのまま動作確認する新規リポジトリには、使うサンプルの**フォルダの中身**をルートへ配置します。既存の実プロジェクトには、ワークフローと必要な補助ファイルを取り込みます。既存の `src/` やビルド定義を使い、ワークフローのパスと引数を合わせます。

どちらの場合もワークフローのパスはリポジトリのルートから見た `.forgejo/workflows/build-release.yml` です。`examples/<サンプル名>/` の階層は含めません。

| サンプル | 配置後に確認・調整するもの |
| --- | --- |
| [Java WAR](examples/java-war-release-template/README.md) | `runs-on`、`JAVA_HOME`、`MAVEN_HOME`、`WAR_BASENAME`、`DEFAULT_REVISION`、WAR の起動・HTTP 検査、`tools/DB/DDL` |
| [C++](examples/cpp-release-sample/README.md) | `runs-on`、CMake のビルド設定、`scripts/runtime-libraries.txt`、`start_MP.sh`、`stop_MP.sh` |

両サンプルの `runs-on` は `el8-mydev` です。組織 Runner のラベルを変更した場合はワークフローも合わせます。ソース取得とリリース登録には、実行時に自動発行される `${{ forgejo.token }}` を使います。現在のサンプルでは個人アクセストークン、リポジトリ Secret、Webhook の追加登録は不要です。[Forgejo Actions のトークン仕様](https://forgejo.org/docs/v15.0/user/actions/reference/)

## 4. Runner 上のビルド環境

Runner は `mydev` ユーザーでホスト上にジョブを実行します。両ワークフローは Forgejo API から対象コミットのアーカイブを取得するため、Runner から API URL に接続でき、`bash`、`curl`、`tar`、`sha256sum` を実行できる必要があります。外部の `uses:` Action は利用しません。

| サンプル | 必要なビルド環境 |
| --- | --- |
| Java WAR | JDK 17、Maven、ビルドに必要な Maven 依存物。サンプルの設定は `JAVA_HOME=/opt/forgejo-java-tools/jdk`、`MAVEN_HOME=/opt/forgejo-java-tools/maven` |
| C++ | CMake、C++ コンパイラ、`make`。実プロジェクトでは `runtime-libraries.txt` に指定した共有ライブラリも Runner 上に置く |

ネットワークを遮断した環境では、Maven の依存物を Runner が参照できるローカルキャッシュまたは内部リポジトリに用意します。Java の WAR 名・HTTP 検査先、C++ の共有ライブラリや配布用シェルは、各サンプルの README に従って実プロジェクトへ合わせます。

## 5. push とリリースを確認する

| 操作 | 実行内容 |
| --- | --- |
| `main` への push | ビルド・テスト・梱包を実行する。リリースは作成しない |
| Actions 画面で `main` から `tag` を入力して手動実行 | 同じ検査の後、タグと Forgejo リリースを作成する |

1. 対象リポジトリの `main` にワークフローを含むコミットを push し、**Actions** に実行が表示されて成功することを確認します。
2. リリースを試す場合は、**Actions** から対象のワークフローを `main` で手動実行し、`tag` を入力します。タグを push するだけではリリースは作成されません。
3. 実行が成功したら、**Releases** でタグ、ZIP、個別ファイル、`SHA256SUMS` を確認します。

ワークフローが表示されなければ配置パスと Actions の有効化を、実行待ちのままなら Runner のオンライン状態とラベルを確認します。ジョブが始まってから失敗した場合は、その実行ログで API 接続、ツールのパス、ビルド依存物、配布対象ファイルを確認します。[Forgejo Actions クイックスタート](https://forgejo.org/docs/v15.0/user/actions/quick-start/)
