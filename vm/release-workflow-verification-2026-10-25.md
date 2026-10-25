# `myproject` リリースワークフロー再検証（2026-10-25）

## 実施範囲

既存の `forgejo-lab` VM を正常停止し、スナップショット「OS準備完了」へ復元して起動した。その後、[準備端末](../preparation.md)、[Forgejo導入](../installation.md)、[組織Runner登録](../myproject-runner-registration.md)、[ワークフロー導入](../forgejo-workflow.md)の順に実施した。復元直後は Oracle Linux 8.10、SELinux `Enforcing`、Forgejo・Runner 未導入だった。

この再検証では、導入手順のコマンド列を作業用の一時シェルにまとめてSSHから実行し、組織・リポジトリの画面操作に相当する登録APIを使った。手順書を人が1行ずつ操作した場合の画面遷移そのものは検証対象外とした。

秘密値、初期パスワード、Runner Token はこの記録に含めない。初期管理者パスワードはGit管理外へ保存し、VM側の一時ファイルを削除した。

## 導入とRunner

- 準備端末のForgejo 15.0.10、Runner 13.2.0、各署名・公開鍵・公式systemdユニットの6ファイルは、手順書のサイズとSHA-256に一致した。VMへの搬入後、ForgejoとRunnerのGPG署名はともに `Good signature`。公開鍵指紋は `EB11 4F5E 6C0D C2BC DD18 3550 A4B6 1A2D C592 3710` と一致した。
- Oracle Linux 8.10用の搬入RPM 49個を署名確認し、外部リポジトリを無効にしてGit 2.43.7とGit LFS 3.4.1を導入した。
- Forgejo 15.0.10とRunner 13.2.0を導入した。ForgejoとRunnerのsystemdサービスは稼働し、Forgejo APIは `15.0.10+gitea-1.22.0` を返した。
- `forgejo-admin`ユーザー単位のRunnerと、非公開組織`myproject`用のRunnerを同じサービスに登録した。組織Runner `myproject-mydev` は `idle`、ラベルは `el8-mydev`。TokenはVM上の`mydev`専用ファイルで管理した。
- サンプル用ビルド環境として、準備端末でハッシュを照合したCorretto 17.0.21とMaven 3.10.0をVMへ搬入した。Maven依存物は準備端末で`mvn clean package`とテスト1件を成功させてから、`mydev`のローカルキャッシュへ搬入した。CMake 3.26.5、GCC C++ 8.5.0、make 4.2.1と依存RPMは、VMに接続したOracle Linux 8.10 DVDをローカルリポジトリとして導入した。ビルドツール取得にVMから外部サイトを使っていない。

## リポジトリとActions

次の各サンプルフォルダの**中身**を、`myproject`配下の独立した非公開リポジトリのルートへ配置した。ワークフローは各リポジトリの`.forgejo/workflows/build-release.yml`にある。

| リポジトリ | `main` の最終コミット | push時Actions | 手動リリースActions |
| --- | --- | --- | --- |
| [`myproject/cpp-release-sample`](http://192.168.131.131:3000/myproject/cpp-release-sample) | `7ada930` | [成功（run 2）](http://192.168.131.131:3000/myproject/cpp-release-sample/actions/runs/2) | [成功（run 3）](http://192.168.131.131:3000/myproject/cpp-release-sample/actions/runs/3) |
| [`myproject/java-war-release-template`](http://192.168.131.131:3000/myproject/java-war-release-template) | `2db5b44` | [成功（run 2）](http://192.168.131.131:3000/myproject/java-war-release-template/actions/runs/2) | [成功（run 3）](http://192.168.131.131:3000/myproject/java-war-release-template/actions/runs/3) |

各リポジトリの初回pushは、ビルドツールの搬入前に行ったためActionsが失敗した。環境を揃えた後、空コミットをpushして両方のActionsが成功した。手動リリースは`main`とタグ`v0.1.0`を指定して起動した。

## リリースページと成果物

| リポジトリ | リリースページ | 添付物の確認 |
| --- | --- | --- |
| C++ | [`v0.1.0`](http://192.168.131.131:3000/myproject/cpp-release-sample/releases/tag/v0.1.0) | 実行ファイル、`cpp-release-sample-0.1.0-linux-x86_64.zip`、`SHA256SUMS`。ZIPに実行ファイル、`start_MP.sh`、`stop_MP.sh`を確認 |
| Java WAR | [`v0.1.0`](http://192.168.131.131:3000/myproject/java-war-release-template/releases/tag/v0.1.0) | `planning-api-0.1.0.war`、`dbscript.tar.gz`、`release-0.1.0.zip`、`SHA256SUMS`。ZIPにWARとDDLアーカイブを確認 |

両リリースは公開状態で、管理者としてWebログインしたリリースページがHTTP 200を返し、添付物名が表示された。添付物を再取得し、C++の2行とJavaの3行の`SHA256SUMS`をすべて照合した。Javaの`dbscript.tar.gz`には`dbscript/DDL/schema.sql`があり、`USER/`と`*_devenv.sh`は含まれなかった。

C++サンプルの`runtime-libraries.txt`には実ライブラリの指定がないため、今回のZIPではライブラリのコピー対象はない。実プロジェクトのライブラリ指定とコピー結果は移植時に確認する。

## 手順上の補足

Forgejo初回起動直後は、サービスが`active`でも`app.ini`に自動生成される3つのトークンが揃うまで短い時間差があった。[導入手順](../installation.md)に最大30秒待って確認するコマンドを追加した。また、[ワークフロー導入手順](../forgejo-workflow.md)のpush時の説明を、C++とJava WARの実際の処理に合わせた。

検証VMはVMware NAT接続であり、物理的なエアギャップ環境そのものの確認ではない。今回のビルドツールは準備端末および接続したDVDから搬入した。
