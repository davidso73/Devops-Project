# Generates the Ansible inventory and variables straight from real deployed
# resources, so `terraform apply` followed by `ansible-playbook` just works
# with no manual copy-pasting of IPs/ARNs/endpoints between the two tools.

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../Ansible/inventory.ini"
  content = templatefile("${path.module}/ansible_templates/inventory.ini.tpl", {
    frontend_public_ip = aws_instance.frontend.public_ip
    backend_private_ip = aws_instance.backend.private_ip
    worker_private_ip  = aws_instance.worker.private_ip
    key_name           = var.key_name
  })
}

resource "local_file" "ansible_group_vars_all" {
  filename = "${path.module}/../Ansible/group_vars/all/vars.yml"
  content = templatefile("${path.module}/ansible_templates/group_vars_all.yml.tpl", {
    aws_region    = var.aws_region
    s3_bucket     = var.s3_bucket_name
    sqs_queue_url = aws_sqs_queue.requests.id
    sns_topic_arn = aws_sns_topic.notifications.arn
    rds_endpoint  = aws_db_instance.vmapp.address
    db_name       = var.db_name
    db_username   = var.db_username
  })
}

resource "local_file" "ansible_group_vars_secrets" {
  filename = "${path.module}/../Ansible/group_vars/all/secrets.yml"
  content = templatefile("${path.module}/ansible_templates/group_vars_secrets.yml.tpl", {
    db_password      = random_password.db.result
    flask_secret_key = random_password.flask_secret.result
  })

  file_permission = "0600"
}
