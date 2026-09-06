resource "aws_ecr_repository" "frontend" {
  name                 = "vmapp-frontend"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Project = "vmapp-eks" }
}

resource "aws_ecr_repository" "backend" {
  name                 = "vmapp-backend"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Project = "vmapp-eks" }
}

resource "aws_ecr_repository" "worker" {
  name                 = "vmapp-worker"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Project = "vmapp-eks" }
}
