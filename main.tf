locals {
  name = "${var.project_name}-${var.environment}"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source = "./modules/vpc"

  name                 = local.name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  cluster_name         = local.name

  tags = local.tags
}

module "ecr" {
  source = "./modules/ecr"

  name = local.name
  tags = local.tags
}

module "eks" {
  source = "./modules/eks"

  cluster_name       = local.name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  node_instance_type = var.node_instance_type
  node_count         = var.node_count
  node_disk_size     = var.node_disk_size

  tags = local.tags
}
