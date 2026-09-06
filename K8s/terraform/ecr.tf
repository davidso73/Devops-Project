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

# Jenkins agent images - pinned, non-root by design, scanned like every
# other image in this project (see Jenkins/agent-images/).
resource "aws_ecr_repository" "ci_tools" {
  name                 = "vmapp-ci-tools"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Project = "vmapp-jenkins" }
}

resource "aws_ecr_repository" "cd_tools" {
  name                 = "vmapp-cd-tools"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Project = "vmapp-jenkins" }
}
