# modern-core-eks-iac / teraform-wfa-apigw

AWS WAFを利用したAPI Gatewayの保護、およびTerraform管理への移行用リポジトリです。

## 1. 概要
API Gatewayに対して特定のIPアドレスのみを許可し、それ以外のトラフィックに対して独自の「Not Found 403」メッセージを返すセキュアなエンドポイントを構築しました。

## 2. 構築内容

### ① API Gateway (`kensho-api`)
- **タイプ**: REST API
- **設定**: GETメソッドを実装し、正常なレスポンスを返却するよう構成。
- **デプロイ**: ステージ環境へのデプロイを完了し、エンドポイントURLを発行。

### ② AWS WAF (`kensho-waf`)
- **IP Set**: 自身の接続元IPアドレスをホワイトリストとして登録。
- **Web ACL ルール**: IP Setに一致しないトラフィックを「Block」に設定。
- **Association**: API GatewayのステージとWeb ACLを紐付け。

### ③ カスタムレスポンス設定
ブロック時の挙動をカスタマイズし、セキュリティの隠蔽性を高めています。
- **レスポンスボディ**: `Not Found 403`
- **レスポンスコード**: `403`
- **意図**: 標準的なブロック画面を隠蔽し、独自の文字列を返すことで、正常にブロックされていることを管理者側で判別しやすくしました。

## 3. Git管理とセキュリティ
将来的な **HCP Terraform (Terraform Cloud)** への移行を見据えた構成としています。

- **機密情報の保護**: `.gitignore` を設定し、以下のファイルをGit管理から除外しています。
  - `terraform.tfstate` (構成情報)
  - `*.tfvars` (変数・機密情報)
  - `*.pem` (認証キー)
- **接続方式**: GitHubへの接続はSSH方式（`git@github.com:...`）を採用。

## 4. 今後の予定
- [ ] 手動設定したWAF/API GatewayのTerraform化（`main.tf`への書き起こし）
- [ ] HCP Terraform への移行とState管理のクラウド化

