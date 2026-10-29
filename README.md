# aws-portfolio-site

![Terraform](https://img.shields.io/badge/Terraform-1.5%2B-7B42BC?logo=terraform)
![AWS](https://img.shields.io/badge/AWS-us--east--1-FF9900?logo=amazonaws)
![Provider](https://img.shields.io/badge/hashicorp%2Faws-~%3E5.0-blue)
![State](https://img.shields.io/badge/state-S3%20remote-green)

Terraform configuration managing the production AWS infrastructure behind
[jmarcelocarvalho.com](https://jmarcelocarvalho.com) and the PerfectSpot subdomain.

This is a **live production environment**, not a lab. No resources were provisioned
from scratch — existing infrastructure was brought under IaC control using
`terraform import`, with zero downtime and zero resources destroyed.

---

## Architecture

```
                        ┌─────────────────────────────┐
                        │        us-east-1            │
                        │                             │
  Internet ──────────▶  │  EIP: 52.44.121.xx          │
                        │  EC2 t3.small (us-east-1a)  │
  SSH (home IP only) ──▶│  ├── Flask + Gunicorn       │
                        │  ├── PerfectSpot (subdomain)│
                        │  ├── PostgreSQL (container) │
                        │  └── Nginx + Let's Encrypt  │
                        │                             │
                        │  Security Group             │
                        │  ├── 80/443 open            │
                        │  └── 22 home IP only        │
                        └─────────────────────────────┘

  Terraform state ──▶  S3: jmarcelo-portfolio-tfstate/EC2_prod/terraform.tfstate
```

---

## Infrastructure managed

| Resource | ID | Description |
|---|---|---|
| `aws_instance` | `i-xxxxxxxx` | EC2 t3.small running the site |
| `aws_eip` | `eipalloc-xxxxxxxx` | Static public IP |
| `aws_eip_association` | `eipassoc-xxxxxxxx` | EIP bound to instance |
| `aws_security_group` | `sg-xxxxxxxx` | Ingress rules |
| `aws_s3_bucket_versioning` | `jmarcelo-portfolio-tfstate` | State bucket versioning |
| `aws_s3_bucket_lifecycle_configuration` | `jmarcelo-portfolio-tfstate` | 30-day noncurrent version expiry |

---

## Stack

| Layer | Technology |
|---|---|
| IaC | Terraform >= 1.5, hashicorp/aws ~> 5.0 |
| Compute | AWS EC2 t3.small, us-east-1a |
| Networking | AWS VPC, Elastic IP, Security Groups |
| Application | Python 3, Flask, Gunicorn |
| Reverse proxy | Nginx |
| TLS | Let's Encrypt via Certbot |
| Containers | Docker, Docker Compose |
| Database | PostgreSQL (containerized) |
| State backend | S3 (no DynamoDB — single operator) |

---

## Repository structure

```
tf_jmarcelo_prod/
├── .gitignore               # excludes *.tfstate, .terraform/, terraform.tfvars
├── .terraform.lock.hcl      # provider version lock
├── provider.tf              # AWS provider, pinned to ~> 5.0, us-east-1
├── backend.tf               # S3 remote state, profile: prod
├── variables.tf             # region, key_name, home_ip (sensitive), IDs
├── terraform.tfvars         # gitignored — real values live here
├── main.tf                  # all resources: EC2, EIP, SG, S3 lifecycle
└── outputs.tf               # instance_id, public_ip, security_group_id
```

---

## How to use

### Prerequisites

- Terraform >= 1.5
- AWS CLI configured with a profile that has EC2, S3, and Route53 access
- SSH key pair registered in AWS (`webserver_key`)
- S3 bucket `jmarcelo-portfolio-tfstate` already exists

### Init

```bash
terraform init
```

The backend will authenticate using the `prod` AWS CLI profile and pull
state from `s3://jmarcelo-portfolio-tfstate/EC2_prod/terraform.tfstate`.

### Plan and apply

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

Always use `-out` to ensure what you reviewed is exactly what gets applied.

### Useful outputs

```bash
terraform output public_ip       # 52.44.121.xx
terraform output instance_id     # i-xxxxxxxx
terraform output security_group_id
```

---

## How this was built — import process

This infrastructure predated Terraform. The EC2 instance, security group, and
Elastic IP were originally provisioned manually through the AWS console. Rather
than rebuilding from scratch and risking downtime, the existing resources were
imported into state.

### Import commands used

```bash
terraform import aws_security_group.portfolio sg-xxxxxxxx
terraform import aws_instance.portfolio       i-xxxxxxxx
terraform import aws_eip.portfolio            eipalloc-xxxxxxxx
```

The `aws_eip_association` resource cannot be imported directly — Terraform
created it cleanly since the association already existed and no re-attachment
occurred.

### Import order matters

Security group was imported first because the EC2 resource block references it
via `vpc_security_group_ids`. Importing the instance before the SG would cause
a dependency resolution error during plan.

---

## Lessons learned

### 1. The security group description is immutable

The original security group was created by the AWS console launch wizard with
an auto-generated description:

```
launch-wizard-1 created 2025-04-02T22:55:28.818Z
```

The initial `main.tf` used a human-readable description instead:

```hcl
description = "Portfolio site security group"   # wrong
```

`terraform plan` flagged this as a `-/+` (destroy and recreate) action —
meaning Terraform would have deleted the live security group and created a new
one, taking the EC2 instance offline in the process.

**Fix:** match the description exactly as AWS stored it. The `description`
attribute on `aws_security_group` is immutable and forces replacement on any
change.

### 2. Never apply a plan containing `-/+` on a live instance

The first plan output showed two destroy-and-recreate actions:
- `aws_instance.portfolio` — caused by `FILL_AFTER_IMPORT` placeholder values
- `aws_security_group.portfolio` — caused by the description mismatch above

Running `terraform show` after import revealed the real AMI ID
(`ami-xxxxxxxx`) and instance type (`t3.small`). The HCL was updated
to match before apply was ever run. Final plan: **1 added, 3 changed,
0 destroyed.**

### 3. S3 backend region must be hardcoded

The AWS CLI profile used on the Terraform VM had `region = us-east-2` (set
during exam study to avoid accidentally modifying production resources). When
`terraform init` ran, it inherited that region and tried to access the state
bucket in `us-east-2`, where it does not exist.

**Fix:** hardcode `region = "us-east-1"` directly in `backend.tf` and
`provider.tf` rather than relying on the CLI profile default. Explicit over
implicit — especially when the same machine manages both lab and production.

### 4. The `filter {}` block is required in lifecycle rules

The initial lifecycle configuration omitted the `filter` block:

```hcl
rule {
  id     = "expire-old-state-versions"
  status = "Enabled"
  noncurrent_version_expiration {
    noncurrent_days = 30
  }
}
```

Terraform flagged this as a warning:

```
No attribute specified when one (and only one) of
[rule[0].filter, rule[0].prefix] is required
```

**Fix:** add an empty `filter {}` block, which tells AWS to apply the rule to
all objects in the bucket. This will become a hard error in a future provider
version — fixing warnings early is cheaper than fixing errors later.

### 5. `us-east-1` S3 bucket creation has no LocationConstraint

Every AWS region except `us-east-1` requires a `--create-bucket-configuration
LocationConstraint=<region>` flag when creating S3 buckets via CLI. Passing
this flag for `us-east-1` returns an error. This is a known AWS inconsistency
worth remembering.

---

## State management

- **Backend:** S3, no DynamoDB locking (single operator — locking overhead not justified)
- **Versioning:** enabled on the state bucket
- **Lifecycle:** noncurrent versions expire after 30 days, managed in Terraform
- **Sensitive values:** `home_ip` marked `sensitive = true` in `variables.tf`,
  never appears in plan output or logs

---

## Next steps

- [x] CI/CD: GitHub Actions deploys via OIDC → SSM from GHCR (see jmarcelocarvalho.com repo)
- [ ] Run `terraform plan` in CI on pull requests
- [ ] Import remaining resources (DNS, IAM)
- [ ] PerfectSpot RDS migration from containerized PostgreSQL

---

## Related repositories

| Repo | Purpose |
|---|---|
| [jmarcelocarvalho.com](https://github.com/jmarcelo81/jmarcelocarvalho.com) | Application code — Flask, Docker, Nginx |
| [terraform-multi-cloud](https://github.com/jmarcelo81/terraform-multi-cloud) | Lab IaC — AWS us-east-2 + OpenStack homelab |
