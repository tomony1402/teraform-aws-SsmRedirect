# Terraform for Ultra Low-Cost Apache Redirect EC2 (Multi-Region)

Terraform を用いて、AlmaLinux 9 ベースの超低コストなリダイレクト専用 EC2 インスタンスを AWS 全リージョンへ展開するための構成です。  
AWS Systems Manager (SSM) を活用した「設定の外部注入」と「完全リモート管理」を実現しています。  

---

## 🎯 プロジェクトの核心

- **超低コスト展開**: Amazon Linux では不可能な「EBS 10GB」構成を AlmaLinux で実現。  
- **SSM 集中管理**: 東京リージョンを「本尊」とし、世界中のインスタンス設定を一括制御。  
- **Local IaC**: HCP Terraform に依存せず、ローカル実行で完結する確実なプロビジョニング。  

---

## 🛠️ 技術的なポイントと設計思想  

### 1. パフォーマンス最適化と起動速度の死守  
- **yum update の制限**  
    - **判断**: 当初は `yum update -y` を検討したが、t2.nano 環境では最新リポジトリのパッケージ肥大化により負荷が激増し、プロビジョニングに膨大な時間を要することを確認。  
    - **解決**: 起動速度を最優先し、更新を必要最小限（`httpd`, `awscli`）に絞り込むことで、AWS ステータスチェックのタイムアウト（1/2 起動遅延）を回避。安定した **「ステータスチェック 2/2 合格」** を確実に達成しました。  

### 2. SSM 集中管理（00_ssm_base による「本尊」設計）
- **一元管理（SSM 本尊）**
    - 全リージョンの設定値（リダイレクト先 URL 等）を、**東京リージョン（ap-northeast-1）** の SSM Parameter Store に集約。  
- **疎結合なディレクトリ構成**  
    - `00_ssm_base`: 設定（本尊）の管理  
    - `01_redirect_compute`: 計算リソース（実体）の管理  
- **運用の利点**  
    - インフラ構成を変更せず、東京の SSM を書き換えて EC2 を再起動（または SSM Automation 一斉実行）するだけで、グローバルな挙動を一括制御できます。  

### 3. 再起動耐性と動的同期（Self-Persistence）  
- **Cloud-init / per-boot の活用**  
    - UserData 内でスクリプト自身を `/var/lib/cloud/scripts/per-boot/` へコピー。  
    - インスタンス再起動のたびに「本尊」から最新設定をプルし直すため、常に最新状態が維持される「自己更新型」として動作します。  
- **フォールバック設計**  
    - SSM 取得失敗時も、Terraform 定義のデフォルト値を採用し、サービスダウンを絶対に防ぐ二段構えです。  

---

## 🏗️ 構成概要

- **OS**: AlmaLinux 9 (Amazon Linux 2023 の EBS 30GB 制約を回避するため採用)  
- **Instance Type**: t2.nano (月額 約600~700円)  
- **Root Volume**: 10GB (gp3) (月額 約120円)  
- **対応リージョン**: AWS 全リージョン（AMI ID を固定せず動的検索で取得）  

---

## 📂 ディレクトリ構成

```text
.
├── 00_ssm_base             # 東京リージョン：設定値（本尊）を一括管理
│   └── main.tf
├── 01_redirect_compute      # 展開先リージョン：計算資源の実体
│   ├── main.tf             # NW構成・SSM連携
│   ├── output.tf
│   └── modules/
│       └── redirect_ec2/    # EC2 インスタンスモジュール
│           ├── main.tf
│           ├── variables.tf
│           └── userdata/
│               └── apache_redirect.sh.tmpl # 起動・同期スクリプト
└── README.md

```

---
## 詳細技術データ  

### 💡 テクニカルコラム：なぜコードだけで公開鍵が登録されるのか？  

Terraformにおける `aws_key_pair` リソースの動作原理は、**「全自動のコピー＆ペースト」**です。  

#### 処理の3ステップ 
1. **生成 (`tls_private_key`)**:  
   Terraformが実行マシンのメモリ上でRSA鍵ペア（秘密鍵と公開鍵のテキストデータ）を生成します。 
2. **橋渡し (`public_key = ...`)**:  
   生成された公開鍵のテキストデータを `aws_key_pair` リソースへ変数として渡します。 
3. **API実行 (`terraform apply`)**:   
   AWSプロバイダーが AWS API（`ImportKeyPair`）を呼び出し、「このテキストを `tf-key` という名前で保存して」とリクエストを投げます。これにより、AWSコンソールの「キーペア」一覧に自動的に表示されるようになります。  

| 役割 | 担当リソース / エンティティ | 内容 |  
| :--- | :--- | :--- |  
| **鍵の製造** | `tls_private_key` | 秘密鍵・公開鍵のペアを生成 |  
| **運搬係** | **Terraform (AWS Provider)** | 公開鍵をAWSの窓口（API）へ送信 |  
| **保管庫** | **AWS (Key Pairs)** | 送られてきた公開鍵を保存・管理 |  

<details> 
<summary>🔍 Terraform での AMI 取得コード</summary> 

```hcl
data "aws_ami" "almalinux" {
  most_recent = true
  owners      = ["764336703387"] # AlmaLinux OS Foundation

  filter {
    name   = "name"
    values = ["AlmaLinux OS 9*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
```
</details>

<details> 
<summary>💻 全リージョンの AMI 存在確認コマンド（AWS CLI）</summary>

```bash
for r in $(aws ec2 describe-regions --query "Regions[].RegionName" --output text); do
  count=$(aws ec2 describe-images \
    --region "$r" \
    --owners 764336703387 \
    --filters "Name=name,Values=AlmaLinux OS 9*" \
    --query "length(Images)" \
    --output text)
  printf "%-20s : %s\n" "$r" "$count"
done
```
</details>
