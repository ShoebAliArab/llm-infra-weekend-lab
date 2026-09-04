# terraform/eks.tf
resource "aws_eks_cluster" "this" {
  name     = "llm-infra-weekend"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.30"

  vpc_config {
    subnet_ids              = concat(module.vpc.public_subnets, module.vpc.private_subnets)
    endpoint_public_access   = true
    endpoint_private_access  = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

resource "aws_eks_node_group" "gpu" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "gpu-t4-nodes"
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = module.vpc.private_subnets

  instance_types = ["g4dn.xlarge"]
  capacity_type  = "ON_DEMAND"

  scaling_config {
    min_size     = 0
    max_size     = 2
    desired_size = 0
  }

  ami_type = "AL2_x86_64_GPU"

  taint {
    key    = "nvidia.com/gpu"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr
  ]
}

output "cluster_name" {
  value = aws_eks_cluster.this.name
}
