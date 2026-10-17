# セキュリティ確認と修正（Issue #2）

確認日: 2026-10-17。対象はこのリポジトリのテーマ A / B、Terraform、起動スクリプト、同梱アプリ、lockfile、公開方法です。元コードは `812c65ca3cfb994fdf0d551c0b0899f9d4cbb544`。AWS アカウント・稼働環境には接続していません。

これはコードレビューと回帰検査の記録です。侵入試験、全依存物の脆弱性検査、本番利用の承認を意味しません。重大度はこのデモを実データや公開環境に転用した場合の影響を含む、定性的な評価です。

## 修正内容

| 重大度 | 問題 | 対応 |
|---|---|---|
| 中 | A: ディレクトリ単位のアプリ ZIP 作成で `.npmrc` 等の想定外ファイルが混入し得る | 実行に必要なソースと lockfile の明示的な許可リストから ZIP を作成。通常の機密ファイルも Git 除外に追加 |
| 高 | B: アプリ Pod 間と Pod からの接続が制限されず、侵害時の横移動範囲が大きい | VPC CNI の NetworkPolicy enforcement を有効化し、retail namespace を default-deny にした上で必要な経路を許可。制約と未検証点は B README に記載 |
| 高 | A/B: 認証のないデモを全 IPv4 に公開でき、証明書未設定でも HTTP で開始する | クライアント CIDR の `/0` を拒否。証明書がない場合は `allow_insecure_http = true` の明示設定を要求。サンプル tfvars では HTTP の危険を説明 |
| 中 | A: API リクエストごとの DB 接続数に上限がなく、接続枯渇を起こし得る | プロセス単位の同時 DB 処理に上限を設け、超過は 503。異常時にも枠を解放する回帰テストを追加 |
| 中 | 継続的な回帰チェックがない | AWS 認証情報なしで unit/static/fmt/validate/mock test を実行する GitHub Actions を追加。公式 Action は commit SHA 固定、権限は `contents: read` |

NetworkPolicy や同時実行上限は、認証・認可、WAF、DDoS 対策、ワークロード専用 IAM/DB 権限の代替にはなりません。コード変更だけで稼働中の環境が保護されるわけでもありません。

`/0` の拒否は誤設定防止です。複数の広い CIDR の組み合わせによる実質的な全世界公開までは検出しません。必要な接続元だけを指定してください。

## 残る重要なリスクと本番移行前の対応

| 重大度 | 未解決事項 | 今回変更しない理由 / 必要な対策 |
|---|---|---|
| 高 | B Catalog → MySQL が非 TLS。`require_secure_transport = OFF` | upstream v1.6.3 の MySQL DSN が TLS 設定を公開していない。ON だけにすると Catalog が接続できない。アプリを改修・検証し、信頼する RDS CA とホスト名検証を有効にしてから DB 側で TLS を必須化 |
| 高 | B Redis は TLS あり、AUTH/ACL なし | upstream の ioredis 接続は認証付き URL を扱えるが、この構成には認証情報の安全な供給・更新経路がない。DB 側の認証だけを追加すると接続できなくなる。最小権限 ACL/既定ユーザーの無効化、Secrets Manager 経由の配送、rotation、パスワードを state に保存しない方法を一緒に実装・検証。Pod policy は被害範囲を減らすが認証は追加しない |
| 高 | A/B アプリが DB 管理ユーザーを利用 | 既存の初期化/migration・ローテーションを壊さず分離するには DB 内の専用ユーザーと migration 役割の設計が必要。最小権限の実行用ユーザー、別 migration 権限、別 Secret、更新手順を追加する |
| 高 | A/B のアプリに利用者認証がない。HTTP デモの opt-in は引き続き利用可能 | 学習用の挙動を保持。実データを入力しない。公開前に認証・認可、ACM/HTTPS、必要に応じ WAF・流量制御を追加。内部 HTTP 通信も別途暗号化設計が必要 |
| 中 | B NetworkPolicy は SG/DB ACL と同じ境界ではない | CNI 標準モードでは Pod 起動時に policy 適用まで許可窓がある。hostNetwork、ノード、他 namespace、許可された HTTPS 宛先までは完全隔離しない。専用ノード/SG for Pods、private endpoint と送信先制限、strict mode を適合性試験後に検討 |
| 中 | コンテナは tag 固定、OS/AMI/add-on の将来更新に依存 | コンテナの pull・SBOM・イメージ CVE スキャン、OS 脆弱性検査は未実施。検証済み digest、署名・来歴、ECR scanning と更新方針が必要。lockfile は既知脆弱性の不存在を保証しない |
| 中 | Terraform state とローカル生成物の保護は利用者側の運用にも依存 | `.gitignore` は暗号化やアクセス制御ではなく、既に追跡済みの秘密も削除しない。非公開の暗号化 state backend、最小権限、監査、plan の保護が必要。漏えい時は削除だけでなく credential rotation を実施 |

## 検証の境界

- CI 再確認（2026-10-17）: [main の GitHub Actions run 39032652841](https://github.com/sts1992/tf-sample/actions/runs/39032652841) で、commit `21b69aeee33b7286f1dfee1bb6f134ed8408940f` の全 5 job が成功。全 4 root の Terraform 整形・初期化・`validate`、A の AWS mock テスト・API 単体テスト・Node 構文、B の静的検査・mutation 回帰テスト・shell 構文を確認しました。実 AWS 環境での動作確認ではありません。
- ローカル再検査: 全 Terraform の `fmt -check -recursive`、A の API 7 テスト、Node 構文、B の静的検査と mutation 回帰テスト、shell 構文が成功。A の依存インストール・Web 本番ビルド・テンプレート評価も成功。
- AWS の `plan` / `apply` / `destroy`、クラスタへの接続、Helm/Kubernetes への書込は行っていません。AWS リソースは作成・変更していません。
- Terraform mock test は AWS provider を mock 化するものです。実際の AWS API、クォータ、権限、NetworkPolicy/ALB の通信、DB migration の成功は保証しません。
- A の npm 依存監査は 2026-10-17 の lockfile に対する npm advisory 検査です。B のコンテナ、AMI、Helm chart、Terraform provider まで含めた監査ではありません。
- ローカル環境の provider 起動制限で `terraform validate` が完了しない場合は、CI 結果と区別します。実行結果と残る制約は PR のチェックおよび各 README / `theme-b-microservices/VALIDATION.md` を参照してください。
- 公開対象ファイルについて AWS access-key ID、private-key header、GitHub/npm token の高確度パターンを簡易検索しました。秘密検出専用ツールによる網羅的な検査ではありません。

## 根拠

- [Issue #2](https://github.com/sts1992/tf-sample/issues/2)
- [Catalog v1.6.3 MySQL DSN](https://github.com/aws-containers/retail-store-sample-app/blob/v1.6.3/src/catalog/repository/repository.go)
- [Checkout v1.6.3 Redis 接続](https://github.com/aws-containers/retail-store-sample-app/blob/v1.6.3/src/checkout/src/checkout/repositories/RedisCheckoutRepository.ts)
- [EKS VPC CNI NetworkPolicy](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy.html)
- [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [その他の公式参照元と同梱ファイル hash](../theme-b-microservices/SOURCES.md)

この変更を適用する前に、差分・plan・費用を担当者が確認してください。実環境での動作確認が終わるまで、実データや本番トラフィックを入れないでください。
