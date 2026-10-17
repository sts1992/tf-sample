# 検証結果

検証日: 2026-10-14。コード生成・ローカル静的検証のみです。

## 成功

- Terraform CLI 1.16.5 linux_amd64 を使用。
- terraform fmt -recursive を実行後、最終の terraform fmt -check -recursive: 終了コード 0。
- 01-infra: terraform init -backend=false -input=false 成功。HashiCorp 署名付き AWS provider 6.68.0。
- 02-platform: 同じ init 成功。HashiCorp 署名付き Helm provider 3.3.0。
- 03-apps: 同じ init 成功。HashiCorp 署名付き Kubernetes provider 3.3.0。
- 3 root の .terraform.lock.hcl を同梱。取得済み provider 本体 / .terraform ディレクトリは配布対象外。
- bash -n scripts/verify-local.sh scripts/restart-db-workloads.sh: 終了コード 0。
- python scripts/check-static.py: 20 項目 PASS。これは文字列・構造・同梱ファイルハッシュの簡易ガードレールであり、provider schema の完全検証ではありません。
- ALB Controller IAM policy JSON の構文と取得時 SHA-256、AWS RDS CA bundle の SHA-256 を確認。
- 公開公式 chart index で ALB 3.6.0 / CSI Driver 1.6.1 / AWS CSI Provider 3.1.4 の存在を確認。
- 公式 Retail Store v1.6.3 の実装と環境変数、DynamoDB key/GSI、Orders→SQS、Redis TLS、PostgreSQL JDBC URL を照合。
- 独立した静的レビューで、EKS API / node / ALB / data SG の経路、IRSA subject/audience、CSI TokenRequest / secret同期、CRD 作成順、Service 作成順、削除順を確認。残る実運用上の制約は README に明記。

## 実行環境の制約で完了しなかったもの

01-infra の terraform validate は provider 起動時に次のエラーになりました。

```
Failed to load plugin schemas
Unrecognized remote plugin message
Failed to read any lines from plugin's stdout
```

同じ実行環境では provider の Unix socket 作成が制限されています。認可された別実行環境での validate 成功を確認していないため、**全 root の完全な terraform validate が成功したとはしていません**。02/03 の provider 実行を必要とする検証も未完了です。

Terraform fmt と init で構文は読み込まれていますが、属性の provider schema 適合、AWS API の制約、実行時権限・クォータ・リージョンのエンジン提供状況まで保証する検証ではありません。適用前に scripts/verify-local.sh をご自身の環境で実行してください。

## 未実施

- AWSアカウント / EKSクラスタへの接続
- 実際の terraform plan / apply / destroy
- Helm install / kubectl apply
- イメージの実際の pull と脆弱性検査
- サービス起動、DB migration、商品・カート・注文のエンドツーエンドテスト
- Secret rotation / フェイルオーバー / 負荷・性能・可用性・侵入テスト

今回の納品物を「本番利用可能」「実AWSでデプロイ検証済み」とみなさないでください。

## 2026-10-17 セキュリティ変更の再検証

- Terraform CLI 1.16.5: `fmt -check -recursive` 成功。
- `python3 scripts/check-static.py`: 41 項目 PASS。CNI enforcement、retail 既定拒否、DNS、各アプリ・data・AWS HTTPS の選択条件、Service/Pod/Ingress port 整合、HTTP opt-in、/0 CIDR 拒否を含みます。
- `python3 scripts/test-security.py`: 3 テスト成功。現在の 21 セキュリティ条件と、制御を取り除く 15 種類の mutation が検出されること、コメント/文字列内の括弧処理を確認しました。
- `bash -n scripts/verify-local.sh scripts/restart-db-workloads.sh` 成功。
- 公式 v1.6.3 アプリ実装、AWS VPC CNI の要件、Kubernetes provider 3.3.0 の NetworkPolicy schema と照合しました。
- 取得済み公式 provider の別ディレクトリを TF_DATA_DIR に指定して 3 root の validate を再試行しましたが、provider の `listen unix /tmp/plugin…: socket: operation not permitted` を再現し、完全 validate は未完了です。ローカル schema 検証のみの実行権限で再試行しても完了しませんでした。

これらはソースレベルのガードであり、Terraform provider schema 検証や通信シミュレーションではありません。AWS / EKS に接続せず、plan/apply、実際の NetworkPolicy 反映・ALB 到達性・DB/Redis 接続・Secret rotation・注文処理は未実施です。変更コードには依存キャッシュ、state、plan、秘密値を含めていません。
