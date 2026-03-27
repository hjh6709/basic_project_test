[gcp_primary]
gcp-main ansible_host=${gcp_ip} tunnel_token=${gcp_token} db_conn=${db_connection}

[aws_bastion]
aws-bastion ansible_host=${bastion_ip}

[aws_nodes]
aws-sub ansible_host=${aws_ip} tunnel_token=${aws_token}
aws-monitor ansible_host=${mon_ip} tunnel_token=${mon_token}

# --- 그룹별 변수 설정 ---

[gcp_primary:vars]
ansible_ssh_private_key_file=../../my_gcp_key

[aws_bastion:vars]
ansible_ssh_private_key_file=../../chilseong-jh.pem

[aws_nodes:vars]
ansible_ssh_private_key_file=../../chilseong-jh.pem
ansible_ssh_common_args='-o ProxyCommand="ssh -W %h:%p -q ubuntu@${bastion_ip} -i ../../chilseong-jh.pem -o StrictHostKeyChecking=no"'

[all:vars]
ansible_user=ubuntu
gcp_project_id="${gcp_project_id}"
cf_client_id="${cf_id}"
cf_client_secret="${cf_secret}"
