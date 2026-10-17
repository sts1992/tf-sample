# AWS 構成図2件の Terraform 実装例

作成日: 2026-10-14

添付された「テーマA Web 3層システム」と「テーマB マイクロサービス／Kubernetes」を、独立して構築できる2つの例に分けています。

## 構成

- [テーマ A: Web 3 層システム](theme-a-web-three-tier/README.md): 2 AZ、外部ALB、Nginx/ReactのWeb EC2 Auto Scaling Group、内部ALB、Node.jsのApp EC2 Auto Scaling Group、Aurora MySQL writer/reader。
- [テーマ B: マイクロサービス / Kubernetes](theme-b-microservices/README.md): EKS上のUI/Catalog/Cart/Checkout/Orders、外部ALB、RDS MySQL/PostgreSQL、DynamoDB、ElastiCache Redis、SQS。AWS基盤とKubernetes側を段階的に構築します。

各フォルダの `README.md` が実行手順と制限の正本です。2つの構成は同時に構築する必要はありません。Terraform stateを共有しないでください。

## 図から補った前提

- リージョンは東京が初期値。変更する場合はリージョンとAZを合わせて設定します。
- 図Bの `Amazon EKS / Amazon ECS` は、タイトルのKubernetesに合わせてEKSを採用しました。
- 図Bの `Amazon MQ / SQS` はSQSを採用しました。ECS版・Amazon MQ版は含みません。
- インスタンスサイズ、CIDR、アクセス元、データ保護などは各構成の変数で調整します。実アカウントID、認証情報、証明書やドメインは付属しません。
- 図Aはアーキテクチャを確認するための独自デモアプリを含みます。図の参考元ワークショップの業務アプリをそのまま再現したものではありません。
- 図BはAWS Retail Store Sample Appの公式実装を参照しています。アプリ／チャートのバージョンと接続設定は同梱手順を参照してください。

## 実行前に必ず確認すること

これはレビュー・検証用のコードです。本番運用の認証、監視、運用設計、バックアップ復旧試験、負荷試験、費用承認を済ませた完成システムではありません。

2026-10-17 の [セキュリティ確認・修正と残存リスク](document/SECURITY_REVIEW.md) も確認してください。証明書なしの HTTP デモには `allow_insecure_http = true` の明示設定が必要です。認証のないデモのため、全 IPv4 (`/0`) を許可するクライアント CIDR は拒否します。

1. AWSプロファイルと対象アカウントを確認してください。既存環境を指定せず、新規リソースとして作成する例です。
2. `terraform.tfvars.example` を参考にアクセス元CIDR等を設定してください。サンプルの値を実際の値へ置き換えてからplanを確認します。
3. 本番公開ではACM証明書・HTTPS・認証を設定してください。HTTPのデモモードで個人情報や実データを扱わないでください。
4. NAT Gateway、ALB、EC2/EKS、DB、キャッシュ等は停止中の操作待ちでも課金されます。無料枠だけで動く例ではありません。サイズ・稼働時間・リージョンをもとに見積もってください。
5. Terraform stateとplanファイルは非公開で管理してください。コードにパスワードを埋め込まなくても、stateにはインフラ構成などの情報が含まれます。
6. 利用後の削除順序、削除保護、最終スナップショット、残存リソースは各READMEの手順で確認してください。

## 検証について

AWSアカウントへの `plan` / `apply` / `destroy` は実行していません。ローカルで実施した検証と、未実施の実環境確認は各構成のREADMEまたは検証記録に明記しています。`terraform validate` の成功だけでは、実アカウントの権限・クォータ・リージョンでのサービス提供・実デプロイ成功は保証できません。

## 参考元

- https://github.com/aws-samples/aws-three-tier-web-architecture-workshop
- https://github.com/aws-containers/retail-store-sample-app

このリポジトリに元画像や認証情報、Terraform state、プロバイダの実行ファイルは含めません。

### この納品での検証結果の要約

- 両構成: Terraformの整形、初期化によるHCL読込・プロバイダ取得、構成図との対応と接続設定のレビューを実施。
- テーマA: 起動スクリプトのテンプレート評価とshell構文、API単体テスト5件、npm依存解決、Reactの本番ビルド、Node構文検査を通過。
- `terraform validate` は実行環境のUnixソケット制限でプロバイダを起動できず、完了していません。Terraformのmockテスト、AWS実環境でのデプロイとアプリ疎通も未検証です。
- テーマBのCatalog→MySQLは公式サンプルの制限で通信TLS未対応です。その他の簡略化もテーマBのREADMEに記載しています。

## GitHub での取り扱い

- 元の納品物（2026-10-14）を基にセキュリティ修正を加えています。依存関係 lockfile と検証上の制限も管理しています。
- `.terraform/`、state、plan、実値の tfvars、`.env`、`node_modules/`、ビルド出力は Git 管理対象外です。`.terraform.lock.hcl` と `terraform.tfvars.example` は管理します。
- AWS への自動デプロイは設定していません。利用者が実行先と費用を確認したうえで、各サンプルの手順を進めてください。
- Pull Request では AWS 認証情報不要の回帰チェックを実行します。チェックの成功はデプロイや本番利用を承認するものではありません。
- 2026-10-17 の登録前確認: Terraform の整形チェック、テーマ A の API 単体テスト 5 件・Node 構文検査、テーマ B の静的チェック 20 項目・shell 構文検査を再実行し、成功しました。これは実 AWS デプロイの検証ではありません。
