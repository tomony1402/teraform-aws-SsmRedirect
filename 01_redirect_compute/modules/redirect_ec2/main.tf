#data "aws_ami" "amazon_linux" {
#  most_recent = true
#  owners      = ["amazon"]
#
#  filter {
#   name   = "name"
#    values = ["al2023-ami-*-x86_64"]
#  }
#}

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


locals {
  redirect_domains = {
   web-34 = "tune-snowboarding.com"
   web-38 = "wc4h16cy93xvaj.net"
   web-39 = "awhmdoqexf.com"
   #web-40 = "agent-miogaginger.com"
   #web-43 = "zpkwtstcucghuy.com"
   #web-48 = "xhykcndqlfsnsk.com"
   #web-51 = "27pckzcv8pccn.com"
   #web-52 = "0udnenw27gp.com"
   #web-53 = "attendance-proper.com"
   #web-54 = "charmingagrarian.com"
   #web-55 = "backboneimpinge.com"
   #web-56 = "abattamzwr-gbjr.com"
   #web-57 = "fdiaksbdibct-hsa.com"
   #web-58 = "lzyqqkjtrjnwqoni-myhj.com"
   #web-62 = "gaqgarcwmoylyxgi-iyzd.com"
   #web-63 = "xtdunfutlqyqyobe-jzgqg.com"
   #web-64 = "madjievaness.com"
   #web-65 = "fbnizkgcn.com"
  }
}

############################
# Security Group
############################
resource "aws_security_group" "redirect" {
  name = "redirect-sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["18.179.138.244/32"] # ← 必要なら自分のIP/32に変える
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

############################
# EC2
############################
#resource "aws_instance" "web" {
#  for_each = local.redirect_domains
#
#  ami           = data.aws_ami.amazon_linux.id
#  instance_type = "t2.nano"
#  key_name      = var.key_name
#
#  associate_public_ip_address = true
#
#  vpc_security_group_ids = [
#    aws_security_group.redirect.id
#  ]
#
#
#  user_data = templatefile(
#    "${path.module}/userdata/apache_redirect.sh.tmpl",
#    {
#      redirect_domain = each.value
#    }
#  )
#
#  tags = {
#    Name = each.key
# }
#}

data "aws_region" "current" {}

resource "aws_instance" "web" {
  for_each = local.redirect_domains

  # ★ AMI を AlmaLinux に変更
  ami           = data.aws_ami.almalinux.id
  instance_type = "t2.nano"
  key_name      = var.key_name

  iam_instance_profile = "ec2-ssm-kondo"
  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.redirect.id
  ]

  # ★ 20GB にできる
  root_block_device {
    volume_size = 10
    volume_type = "gp3"
  }

   user_data = templatefile(
    "${path.module}/userdata/apache_redirect.sh.tmpl",
    {
      # each.value（ドメイン名）ではなく、each.key（kensho1, kensho2など）を渡す
      target_id       = each.key    # "kensho1" など
      fallback_domain = each.value  # "tune-snowboarding.com" など
      region          = data.aws_region.current.name
    }
  )

  tags = {
    Name = each.key
  }
}
