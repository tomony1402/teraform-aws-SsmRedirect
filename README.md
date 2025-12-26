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

プロジェクトを支える核心的な技術仕様と自動化の仕組みをまとめています。

---

### 1. セキュリティと権限管理 (Security & IAM)

このプロジェクトでは、**「実行リソース（EC2）」**と**「操作ユーザー（IAM User）」**の両方に最小権限（Least Privilege）を適用しています。

<details>
<summary>📋 IAM インスタンスプロファイルと権限ポリシーの詳細</summary>

#### A. EC2 インスタンス側の権限
EC2が起動時に、SSM Parameter Store からデータを安全に取得するための設定です。

- **役割**: 東京リージョンの SSM Parameter Store からリダイレクト設定を動的に取得。
- **制限**: 特定のパス（`/redirect/*`）のみ読み取りを許可し、他のパラメータへのアクセスを遮断。

```hcl
# インスタンスプロファイルの定義
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2-ssm-kondo"
  role = aws_iam_role.ec2_role.name
}
```


#### B. 操作ユーザー側の権限 (IAM Userへ直接付与)
管理者がリソースを構築・管理するために必要な、作業者側の権限設定です。

- **`iam:PassRole`**: 
  作成した IAM ロール（`ec2-ssm-kondo`）を EC2 インスタンスに安全に紐付ける（受け渡す）ための必須権限です。
- **`ssm:GetParameter*`**: 
  管理者が SSM Parameter Store の値を直接確認したり、構築・デバッグ時に値を参照したりするために必要です。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::276164042029:role/ec2-ssm-kondo"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ],
      "Resource": "arn:aws:ssm:ap-northeast-1:276164042029:parameter/redirect/*"
    }
  ]
}
```
</details>

<details>
<summary>💡 テクニカルコラム：なぜコードだけで公開鍵が登録されるのか？</summary>

Terraformにおける `aws_key_pair` リソースの動作原理は、**「全自動のコピー＆ペースト」**です。

<details>
<summary>1. **生成 (`tls_private_key`)**: 実行マシンのメモリ上でRSA鍵ペア（秘密鍵と公開鍵）を生成します。</summary>

```hcl
resource "tls_private_key" "ssh" {
   algorithm = "RSA"
   rsa_bits  = 4096
}
```

 </details>

 <details>
<summary>2. **橋渡し (public_key = ...)**: データの受け渡し</summary>

手元で作った「公開鍵」のテキストデータを、AWS側のリソースへ「コピー＆ペースト」する工程です。

```hcl
resource "aws_key_pair" "ssh" {
  key_name   = "tf-key"
  # 💡 手順1で作ったリソース名(tls_private_key.ssh)を指定してデータを引用
  public_key = tls_private_key.ssh.public_key_openssh
}
```

 </details>

 <details>
<summary>3. **API実行 (terraform apply)**: AWSへの登録完了</summary>

「手元のデータ」が正式に「AWSのリソース」として命を吹き込まれる最終工程です。

1. **リクエストの発信**:
   `terraform apply` を実行すると、Terraform（AWS Provider）が裏側で AWS の **`ImportKeyPair`** という名前のAPI（通信窓口）を呼び出します。
2. **データの送信**:
   手順2で準備した「公開鍵のテキストデータ」を、「`tf-key` という名前で保存して！」というメッセージと一緒にAWSのサーバーへ送り届けます。
3. **AWS側の処理**:
   AWSは受け取ったデータを自分のデータベースに保存し、これで初めてAWSマネジメントコンソールの「キーペア」一覧にあなたの鍵が表示されるようになります。

| ステップ | 状態 | 場所 |
| :--- | :--- | :--- |
| **1. 生成** | 鍵のデータが誕生 | あなたのPCのメモリ内 |
| **2. 橋渡し** | データの形を整えて準備 | Terraformのプログラム内 |
| **3. API実行** | **鍵がAWSの資産になる** | **AWSクラウドのデータベース** |

> **Point**: この一連の流れがあるからこそ、私たちはAWSコンソールを一度も開くことなく、安全かつ確実に鍵を管理できるのです。

 </details>

</details>

---

### 2. AMI の自動検索ロジック (Dynamic AMI Discovery)

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

---

### 3. EC2 インスタンスの量産と自動設定 (IaC & UserData)

これまでに定義した「権限」「鍵」「AMI」を組み合わせ、実際のサービス基盤を自動構築するメインロジックです。

<details>
<summary>🔄 for_each による EC2 の動的量産ロジック</summary>

単一のコードブロックで、定義されたドメインの数だけインスタンスを自動生成する仕組みです。

- **DRY原則の徹底**: `local.redirect_domains` というマップ（変数）を書き換えるだけで、サーバーの増減が可能。
- **動的な紐付け**: `each.key` を活用し、インスタンス名、タグ、UserDataの中身を個別に自動設定します。

```hcl
resource "aws_instance" "web" {
  for_each = local.redirect_domains

  # AMI の動的取得と最小スペックの選択
  ami           = data.aws_ami.almalinux.id
  instance_type = "t2.nano"
  key_name      = var.key_name

  # 権限とネットワーク設定
  iam_instance_profile        = "ec2-ssm-kondo"
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.redirect.id]

  # ルートボリュームの設定
  root_block_device {
    volume_size = 10
    volume_type = "gp3"
  }

  # インスタンスごとの固有設定を UserData に注入
  user_data = templatefile(
    "${path.module}/userdata/apache_redirect.sh.tmpl",
    {
      target_id       = each.key    # "kensho1" などの識別子
      fallback_domain = each.value  # "tune-snowboarding.com" などの実ドメイン
      region          = data.aws_region.current.name
    }
  )

  tags = {
    Name = each.key
  }
}

```

</details>

<details>
<summary>💻 UserData による Apache 自動設定スクリプト</summary>

Terraform から注入された変数を利用し、OS起動時に最新のパラメータを反映させるためのテンプレートファイル（`.sh.tmpl`）の内容です。

- **変数の埋め込み**: `${target_id}` や `${region}` は、Terraform の `templatefile` 関数によって実行時に実際の値へ置換されます。
- **動的な設定生成**: 取得したリダイレクト先 URL に基づき、Apache の `VirtualHost` 設定をその場で書き出します。

#### 📄 apache_redirect.sh.tmpl (抜粋)

```bash
#!/bin/bash
set -eux

# AWS CLI がない場合はインストールする
yum install -y awscli

# 1. AWS CLI を使って SSM からリダイレクト先を取得
ID="${target_id}"            # Terraformから注入 (例: kensho1)
FALLBACK="${fallback_domain}" # Terraformから注入 (例: tune-snowboarding.com)
SSM_REGION="${region}"

# SSM Parameter Store から値を取得
SSM_VALUE=$(aws ssm get-parameter --name "/redirect/$ID/url" --query "Parameter.Value" --output text --region $SSM_REGION 2>/dev/null || echo "")

if [ -n "$SSM_VALUE" ]; then
    TARGET_URL="$SSM_VALUE"
else
    TARGET_URL="$FALLBACK"
fi

# 2. Apache のインストールと設定
yum install -y httpd
systemctl enable --now httpd

# 複数ポート(8080)の待ち受け設定
if ! grep -q "^Listen 8080" /etc/httpd/conf/httpd.conf; then
  echo "Listen 8080" >> /etc/httpd/conf/httpd.conf
fi

# 3. 取得した $TARGET_URL を使って設定ファイルを生成
cat > /etc/httpd/conf.d/redirect.conf << EOL
<VirtualHost *:80>
    Redirect permanent / http://\$TARGET_URL/
</VirtualHost>

<VirtualHost *:8080>
    Redirect permanent / http://\$TARGET_URL/
</VirtualHost>
EOL

systemctl restart httpd

# 自分自身を「再起動のたび」に実行されるフォルダにコピー（永続化）
cp "\$0" /var/lib/cloud/scripts/per-boot/redirect_sync.sh
chmod +x /var/lib/cloud/scripts/per-boot/redirect_sync.sh
```

</details>
