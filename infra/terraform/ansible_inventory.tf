resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    # 1. GCP — 테스트 시 임시값 사용
    gcp_ip         = "0.0.0.0"
    gcp_token      = ""
    db_connection  = ""

    # 2. AWS
    bastion_ip     = module.aws.bastion_public_ip
    aws_ip         = module.aws.k3s_private_ip
    mon_ip         = module.aws.monitoring_private_ip
    aws_token      = module.cloudflare.aws_tunnel_token
    mon_token      = module.cloudflare.monitoring_tunnel_token
    cf_id          = module.cloudflare.cf_access_client_id
    cf_secret      = module.cloudflare.cf_access_client_secret

    # 3. 기타
    gcp_project_id = var.gcp_project_id
  })

  filename = "${path.module}/../ansible/inventory.ini"
}
