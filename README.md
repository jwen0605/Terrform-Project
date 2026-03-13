# AWS EKS Terraform Project

Deploy a containerized application on AWS EKS with 2 worker nodes spread across 2 Availability Zones for high availability.

## Architecture

```
                        ┌─────────────────────────────────────────┐
                        │                  VPC                     │
                        │         10.0.0.0/16  (us-east-1)        │
                        │                                          │
                        │   AZ: us-east-1a      AZ: us-east-1b    │
                        │  ┌─────────────┐   ┌─────────────┐      │
                        │  │ Public Sub  │   │ Public Sub  │      │
                        │  │ 10.0.101/24 │   │ 10.0.102/24 │      │
                        │  │  [NAT GW]   │   │  [NAT GW]   │      │
                        │  └──────┬──────┘   └──────┬──────┘      │
                        │         │                  │             │
                        │  ┌──────▼──────┐   ┌──────▼──────┐      │
                        │  │ Private Sub │   │ Private Sub │      │
                        │  │ 10.0.1.0/24 │   │ 10.0.2.0/24 │      │
                        │  │  [Node 1]   │   │  [Node 2]   │      │
                        │  └─────────────┘   └─────────────┘      │
                        └─────────────────────────────────────────┘
                                       │
                              ┌────────▼────────┐
                              │   EKS Control   │
                              │      Plane      │
                              │  (AWS Managed)  │
                              └─────────────────┘

                              ┌─────────────────┐
                              │   ECR Registry  │
                              │  (Docker Images)│
                              └─────────────────┘
```

## Resources Created

| Resource | Details |
|---|---|
| VPC | 1x, CIDR `10.0.0.0/16` |
| Subnets | 2x public + 2x private (one per AZ) |
| NAT Gateways | 2x (one per AZ for HA) |
| EKS Cluster | Kubernetes 1.29, private + public endpoint |
| Worker Nodes | 2x `t3.medium`, 20 GB disk each |
| ECR Repository | Private, scan-on-push enabled |
| IAM Roles | Cluster role + Node role |

## Why 2 Availability Zones?

With 2 AZs, each node sits in a separate data center. If one AZ goes down, the other node keeps your application running. The only extra cost is a second NAT Gateway (~$32/month), which is a worthwhile trade-off for production workloads.

## Cost Estimate (us-east-1, monthly)

| Resource | ~Cost |
|---|---|
| EKS Control Plane | $73 |
| 2x t3.medium EC2 | $60 |
| 2x NAT Gateway | $64 |
| EBS Storage (2x 20 GB) | $4 |
| ECR Storage | $1 |
| **Total** | **~$202/month** |

## CI/CD with GitHub Actions

Every push to `main` automatically runs `terraform plan` and `terraform apply`. Pull requests only run `plan` (no apply), so you can review changes before merging.

```
Push to main  →  Init → Format Check → Validate → Plan → Apply
Open PR       →  Init → Format Check → Validate → Plan (stops here)
```

### One-time Setup

**1. Enable S3 remote state** (required — GitHub Actions has no local state file):

```bash
cp backend.tf.example backend.tf
# Fill in your S3 bucket name and DynamoDB table
```

**2. Create AWS OIDC trust** (allows GitHub Actions to assume an IAM role without storing credentials):

```bash
# In AWS Console → IAM → Identity Providers → Add Provider
# Provider URL: https://token.actions.githubusercontent.com
# Audience: sts.amazonaws.com
```

Then create an IAM role with the following trust policy:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:<YOUR_GITHUB_ORG>/<YOUR_REPO>:*"
    }
  }
}
```

Attach permissions: `eks:*`, `ec2:*`, `iam:*`, `ecr:*`, `logs:*`, `s3:*`.

**3. Add GitHub secret**:

```
GitHub repo → Settings → Secrets and variables → Actions → New repository secret
Name:  AWS_ROLE_ARN
Value: arn:aws:iam::<ACCOUNT_ID>:role/<YOUR_ROLE_NAME>
```

### Workflow File

Located at [.github/workflows/terraform.yml](.github/workflows/terraform.yml).

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured with sufficient IAM permissions
- [kubectl](https://kubernetes.io/docs/tasks/tools/) for interacting with the cluster
- [Docker](https://docs.docker.com/get-docker/) for building and pushing images

### Required IAM Permissions

Your AWS credentials need permissions for: `eks:*`, `ec2:*`, `iam:*`, `ecr:*`, `logs:*`.

## Usage

### 1. Configure variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 2. (Optional) Configure remote state

```bash
cp backend.tf.example backend.tf
# Uncomment and fill in your S3 bucket details
```

### 3. Deploy

```bash
terraform init
terraform plan
terraform apply
```

> EKS takes ~15 minutes to provision. Node group takes an additional ~5 minutes.

### 4. Connect to the cluster

```bash
aws eks update-kubeconfig --region us-east-1 --name myapp-prod
kubectl get nodes
```

You should see 2 nodes, each in a different AZ:

```
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-1-x.ec2.internal      Ready    <none>   5m    v1.29.x
ip-10-0-2-x.ec2.internal      Ready    <none>   5m    v1.29.x
```

### 5. Push your Docker image to ECR

```bash
# Authenticate Docker with ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <ecr-url>

# Build and push
docker build -t myapp .
docker tag myapp:latest <ecr-url>:latest
docker push <ecr-url>:latest
```

The ECR URL is printed in Terraform outputs after `terraform apply`.

### 6. Deploy your application to Kubernetes

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: myapp
      containers:
        - name: myapp
          image: <ecr-url>:latest
          ports:
            - containerPort: 8080
```

```bash
kubectl apply -f deployment.yaml
```

## Outputs

After `terraform apply`, you will see:

| Output | Description |
|---|---|
| `cluster_name` | EKS cluster name |
| `cluster_endpoint` | Kubernetes API server URL |
| `ecr_repository_url` | ECR URL to push Docker images |
| `configure_kubectl` | Ready-to-run kubeconfig command |
| `docker_login_command` | Ready-to-run ECR login command |

## Tear Down

```bash
terraform destroy
```

> Make sure to delete any Kubernetes LoadBalancer services first, as they create AWS resources that Terraform does not manage.

## Project Structure

```
.
├── .github/
│   └── workflows/
│       └── terraform.yml     # GitHub Actions CI/CD pipeline
├── main.tf                   # Module wiring
├── variables.tf              # Input variables
├── outputs.tf                # Output values
├── providers.tf              # AWS + Kubernetes providers
├── versions.tf               # Provider version pins
├── terraform.tfvars.example  # Variable template
├── backend.tf.example        # Remote state template
└── modules/
    ├── vpc/                  # VPC, subnets, NAT gateways
    ├── eks/                  # EKS cluster, node group, IAM
    └── ecr/                  # ECR repository
```
