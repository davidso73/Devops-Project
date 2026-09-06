resource "random_password" "db" {
  length  = 20
  special = false
}

# Shared across all gunicorn workers via the Ansible-templated env file - without
# this, each worker process would sign session cookies with its own random key
# (Flask's fallback), so a login would randomly "not stick" depending on which
# worker handled the next request.
resource "random_password" "flask_secret" {
  length  = 32
  special = false
}

resource "aws_db_subnet_group" "vmapp" {
  name       = "vmapp-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Project = "vmapp"
  }
}

resource "aws_db_instance" "vmapp" {
  identifier     = "vmapp-db"
  engine         = "postgres"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.vmapp.name
  vpc_security_group_ids = [var.existing_rds_sg_id]
  publicly_accessible    = false

  skip_final_snapshot = true

  tags = {
    Project = "vmapp"
  }
}
