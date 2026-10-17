# 確認した公式ソース

確認日: 2026-10-14。公開公式情報の参照のみ。AWSアカウントやクラスタには接続していません。

## 構成とアプリ互換性

- [AWS Containers Retail Store Sample App](https://github.com/aws-containers/retail-store-sample-app) / [v1.6.3](https://github.com/aws-containers/retail-store-sample-app/releases/tag/v1.6.3)
- [UI の接続先環境変数](https://github.com/aws-containers/retail-store-sample-app/blob/v1.6.3/src/ui/chart/templates/configmap.yml)
- [Catalog の設定変数](https://github.com/aws-containers/retail-store-sample-app/blob/v1.6.3/src/catalog/config/config.go)
- [Catalog の MySQL DSN](https://github.com/aws-containers/retail-store-sample-app/blob/v1.6.3/src/catalog/repository/repository.go): この実装は MySQL TLS オプションを設定していません。
- [Cart の DynamoDB key / index](https://github.com/aws-containers/retail-store-sample-app/blob/v1.6.3/src/cart/src/main/java/com/amazon/sample/carts/repositories/dynamo/entities/DynamoItemEntity.java) / [Cart の table 操作](https://github.com/aws-containers/retail-store-sample-app/blob/v1.6.3/src/cart/src/main/java/com/amazon/sample/carts/services/DynamoDBCartService.java)
- [Checkout の環境変数](https://github.com/aws-containers/retail-store-sample-app/blob/v1.6.3/src/checkout/src/config/configuration.ts) / [Redis 接続実装](https://github.com/aws-containers/retail-store-sample-app/blob/v1.6.3/src/checkout/src/checkout/repositories/RedisCheckoutRepository.ts) / [Redis TLS の chart 設定](https://github.com/aws-containers/retail-store-sample-app/blob/v1.6.3/src/checkout/chart/templates/configmap.yaml)
- [Orders の JDBC URL 構築](https://github.com/aws-containers/retail-store-sample-app/blob/v1.6.3/src/orders/src/main/java/com/amazon/sample/orders/config/DataSourceConfig.java) / [DB property 名](https://github.com/aws-containers/retail-store-sample-app/blob/v1.6.3/src/orders/src/main/java/com/amazon/sample/orders/config/DatabaseProperties.java)
- [Orders の SQS 設定](https://github.com/aws-containers/retail-store-sample-app/blob/v1.6.3/src/orders/src/main/java/com/amazon/sample/orders/config/messaging/SqsMessagingConfig.java) / [SQS送信実装](https://github.com/aws-containers/retail-store-sample-app/blob/v1.6.3/src/orders/src/main/java/com/amazon/sample/orders/messaging/sqs/SqsMessagingProvider.java)

アプリの公式 Helm values と実装も確認していますが、Orders chart は SQS topic 用の value を公開していません。そのためアプリ層は自前の Terraform Kubernetes Deployment / Service を使い、ソースで確認した環境変数を明示しています。存在しない Helm value を設定して動いたことにしている構成ではありません。イメージは公式 release tag に合わせた 1.6.3 を参照します。レジストリ pull とアプリ実行は未検証です。

## Kubernetes / コントローラー / Secret

- [EKS 標準サポート版](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions-standard.html): 既定 1.35。デプロイ前に提供状況・標準サポート期限を再確認。
- [ALB Controller v3.6.0](https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/tag/v3.6.0) / [同版の IAM policy](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v3.6.0/docs/install/iam_policy.json)
- [AWS EKS Helm chart index](https://aws.github.io/eks-charts/index.yaml): ALB chart 3.6.0 を確認。
- [CSI Driver chart index](https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts/index.yaml): chart 1.6.1 を確認。
- [AWS CSI Provider chart index](https://aws.github.io/secrets-store-csi-driver-provider-aws/index.yaml): chart 3.1.4 を確認。
- [ASCP と IRSA](https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_ascp_irsa.html)
- [AWS CSI Provider Helm values](https://github.com/aws/secrets-store-csi-driver-provider-aws/blob/main/charts/secrets-store-csi-driver-provider-aws/values.yaml): 独立 CSI Driver に必要な TokenRequest audiences を確認。
- [AWS RDS global CA bundle](https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem)

## Terraform

- [AWS provider 6.68.0](https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs)
- [Kubernetes provider 3.3.0](https://registry.terraform.io/providers/hashicorp/kubernetes/3.3.0/docs)
- [Helm provider 3.3.0](https://registry.terraform.io/providers/hashicorp/helm/3.3.0/docs)

上記 provider は terraform init で公式署名が検証されたものを選択。バージョンと各プラットフォーム checksum を .terraform.lock.hcl に保存しています。Terraform CLI 1.16.5 を使用しました。

## 同梱外部ファイル

- 01-infra/policies/aws-load-balancer-controller-v3.6.0.json
  - 取得元: ALB Controller v3.6.0 の上記公式 IAM policy
  - SHA-256: 16f232c9d9f79366fe949c4550ad517a202380058a9e48d45a4e215044a20a6a
  - ライセンス: upstream Apache-2.0。LICENSE-Apache-2.0.txt 参照。
- 03-apps/certs/global-bundle.pem
  - 取得元: AWS RDS の上記公開 CA truststore
  - SHA-256: fe45bbebf92ad3e27a583bbb2ddd1553c521ed4d49af5514dc0a40372ea5395c
  - 秘密鍵・ユーザー証明書ではありません。AWS が更新する公開 CA bundle です。

Retail Store のソースとコンテナは upstream の [MIT-0 License](https://github.com/aws-containers/retail-store-sample-app/blob/v1.6.3/LICENSE) および各依存ソフトのライセンスに従います。
