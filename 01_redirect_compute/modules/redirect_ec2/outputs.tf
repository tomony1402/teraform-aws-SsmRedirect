output "public_ips" {
  value = {
    for name, inst in aws_instance.web :
    name => inst.public_ip
  }
}
