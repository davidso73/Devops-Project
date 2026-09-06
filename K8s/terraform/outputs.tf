output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "build_host_public_ip" {
  value = aws_instance.build_host.public_ip
}

output "ecr_frontend_repo_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "ecr_backend_repo_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "ecr_worker_repo_url" {
  value = aws_ecr_repository.worker.repository_url
}

output "irsa_backend_role_arn" {
  value = aws_iam_role.irsa_backend.arn
}

output "irsa_worker_role_arn" {
  value = aws_iam_role.irsa_worker.arn
}

output "irsa_lbc_role_arn" {
  value = aws_iam_role.irsa_lbc.arn
}

output "irsa_jenkins_ci_role_arn" {
  value = aws_iam_role.irsa_jenkins_ci.arn
}
