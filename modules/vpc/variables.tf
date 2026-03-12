variable "name" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "availability_zones" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "cluster_name" {
  description = "EKS cluster name — used in subnet tags for discovery"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
