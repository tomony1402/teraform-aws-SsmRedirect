terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

# 画像のモジュールをループ(for_each)で使う
module "ssm_parameters" {
  source  = "terraform-aws-modules/ssm-parameter/aws"
  version = "~> 1.1.0" # 現在の安定版

  for_each = {
    web-34 = "tune-snowboarding.com"
    web-38 = "wc4h16cy93xvaj.net"
    web-39 = "awhmdoqexf.com"
    web-40 = "agent-miogaginger.com"
    web-43 = "zpkwtstcucghuy.com"
    web-48 = "xhykcndqlfsnsk.com"
    web-51 = "27pckzcv8pccn.com"
    web-52 = "0udnenw27gp.com"
    web-53 = "attendance-proper.com"
    web-54 = "charmingagrarian.com"
    web-55 = "backboneimpinge.com"
    web-56 = "abattamzwr-gbjr.com"
    web-57 = "fdiaksbdibct-hsa.com"
    web-58 = "lzyqqkjtrjnwqoni-myhj.com"
    web-62 = "gaqgarcwmoylyxgi-iyzd.com"
    web-63 = "oonp.alive-netksee.com"
    web-64 = "madjievaness.com"
    web-65 = "fbnizkgcn.com"
  }

  name  = "/redirect/${each.key}/url"
  value = each.value
  type  = "String"

  # モジュール内のリソースにlifecycleを渡すのは難しいため
  # このモジュール自体を「消さない運用」で管理します
}
