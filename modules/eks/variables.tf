variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs (one per AZ) where nodes will run"
  type        = list(string)
}

variable "node_instance_type" {
  type = string
}

variable "node_count" {
  type = number
}

variable "node_disk_size" {
  type = number
}

variable "tags" {
  type    = map(string)
  default = {}
}
