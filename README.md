# infra-repo

Terraform configuration that provisions a 3-AZ AWS VPC, an Ubuntu EC2 instance, a security group, an SSH key pair and an S3 bucket in the **ap-south-2 (Hyderabad)** region, with Terraform state stored remotely in S3.

> **Cost warning:** `terraform apply` creates billable resources. The **NAT gateway** is charged per hour plus per GB of traffic, even when idle. The EC2 instance and public IPv4 addresses are also billed. Run `terraform destroy` when you finish.

---

## What it provisions

| File | Resource(s) | Details |
|---|---|---|
| `vpc.tf` | `terraform-aws-modules/vpc/aws` module | VPC `10.0.0.0/16` named `terraform-vpc` across `ap-south-2a/b/c`. Has 3 public subnets (`10.0.101-103.0/24`) and 3 private subnets (`10.0.1-3.0/24`). Adds an Internet Gateway, a **single** NAT gateway with its Elastic IP, route tables and a VPN gateway. DNS hostnames and DNS support are on, and instances in public subnets get public IPs. |
| `Sec_Group.tf` | `aws_security_group.demo_sg` | `demo-sg`. Allows inbound SSH (22) and HTTP (80) from `0.0.0.0/0` and all outbound traffic. |
| `instance.tf` | `data.aws_ami.ubuntu`, `aws_instance.terraform_instance` | Looks up the latest Canonical **Ubuntu 22.04 (Jammy)** AMI and launches a `t3.micro` with the key pair and security group attached. Tag: `Name = terraform-instance`. |
| `key_pair.tf` | `aws_key_pair.student_key` | Uploads your local public key `~/.ssh/id_rsa.pub` to AWS as `student-key`. |
| `S3bucket.tf` | `aws_s3_bucket.bucket1120027788` | Creates the S3 bucket `my-tf-test-bucket1120027788` with tags `Name` and `Environment = Dev`. |
| `backend.tf` | S3 backend | Stores state at `s3://backend-state-1122/terraform/terraform.tfstate` and uses S3-native state locking (`use_lockfile = true`). |
| `Providers.tf` | AWS provider | `hashicorp/aws ~> 6.0` (the lock file pins 6.58.0), region `ap-south-2`. |
| `vars.tf` | Input variables | VPC name and CIDR, the 3 AZs and the 6 subnet CIDRs, all with defaults. |

### Layout

```
                    ap-south-2  (VPC 10.0.0.0/16 "terraform-vpc")
 ┌──────────────────────────────────────────────────────────────────────┐
 │  AZ a                    AZ b                    AZ c                  │
 │  public 10.0.101.0/24    public 10.0.102.0/24    public 10.0.103.0/24  │──► Internet Gateway
 │    └─ NAT gateway (single, shared by all private subnets)             │
 │  private 10.0.1.0/24     private 10.0.2.0/24     private 10.0.3.0/24   │──► NAT ──► Internet
 └──────────────────────────────────────────────────────────────────────┘

 EC2 t3.micro (Ubuntu 22.04) + demo-sg + student-key   ← launched in the DEFAULT VPC (see Known limitations)
 S3 bucket my-tf-test-bucket1120027788
 Remote state: s3://backend-state-1122/terraform/terraform.tfstate
```

---

## Repository structure

```
.
├── .gitignore            # ignores .terraform/, *.tfstate, *.tfvars, plan files, crash logs
├── .terraform.lock.hcl   # pins the AWS provider version + hashes (committed on purpose)
├── Providers.tf          # terraform/required_providers block + AWS provider (region)
├── backend.tf            # remote state in S3 with native lockfile
├── vars.tf               # VPC/subnet/AZ variables with defaults
├── vpc.tf                # VPC built with the community terraform-aws-modules/vpc module
├── Sec_Group.tf          # security group: SSH + HTTP in, all out
├── key_pair.tf           # imports ~/.ssh/id_rsa.pub as an AWS key pair
├── instance.tf           # Ubuntu AMI lookup + EC2 instance
└── S3bucket.tf           # demo S3 bucket
```

---

## Prerequisites

- **Terraform 1.10 or newer.** `use_lockfile` in the S3 backend needs 1.10+.
- **AWS CLI** configured with credentials (`aws configure`) that can manage VPC, EC2, S3 and key pairs.
- The **ap-south-2 region enabled** on your account. Hyderabad is an opt-in region.
- An SSH key pair at `~/.ssh/id_rsa` / `~/.ssh/id_rsa.pub`. To create one:
  ```bash
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
  ```
- **The state bucket must already exist.** Terraform does not create its own backend bucket. The bucket `backend-state-1122` already exists in my account. If you fork this repo, create your own bucket and change the name in `backend.tf`:
  ```bash
  aws s3api create-bucket --bucket <your-state-bucket> --region ap-south-2 \
    --create-bucket-configuration LocationConstraint=ap-south-2
  aws s3api put-bucket-versioning --bucket <your-state-bucket> \
    --versioning-configuration Status=Enabled
  ```

## How to run

```bash
terraform init      # downloads the AWS provider + VPC module, connects to the S3 backend
terraform fmt       # formats the .tf files
terraform validate  # checks syntax and references
terraform plan      # shows what will be created
terraform apply     # creates the resources (type "yes")
```

This config has no `outputs.tf`, so get the instance's public IP and SSH in like this:

```bash
terraform state show aws_instance.terraform_instance | grep public_ip
ssh -i ~/.ssh/id_rsa ubuntu@<public_ip>
```

**Clean up** (do this every time you finish practising):

```bash
terraform destroy
```

The state bucket `backend-state-1122` is not managed by this config, so `destroy` leaves it in place. It costs very little, but delete it manually if you no longer need it.

---

## What I learned

- **Using a community module.** `terraform-aws-modules/vpc/aws` creates the VPC, subnets, IGW, NAT, route tables and their associations from about 20 lines of input. Writing each of those resources by hand takes far more code.
- **Public vs private subnets.** Public subnets route to an Internet Gateway. Private subnets reach the internet only outbound, through a NAT gateway. `single_nat_gateway = true` trades high availability for lower cost.
- **Data sources.** `data "aws_ami"` looks up the latest Ubuntu image at plan time instead of hardcoding an AMI ID, which differs per region.
- **Resource references create dependencies.** `aws_key_pair.student_key.key_name` and `aws_security_group.demo_sg.id` tell Terraform to create those resources before the instance.
- **Remote state with locking.** State lives in S3, not on my laptop, and `use_lockfile` stops two `apply` runs from changing state at the same time.
- **What not to commit.** `.tfstate` (it can contain secrets and resource IDs), `.terraform/` and `*.tfvars` are git-ignored. `.terraform.lock.hcl` **is** committed so everyone uses the same provider version.
- **The core workflow:** `init → validate → plan → apply → destroy`.

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `terraform init` fails with an error that the S3 bucket does not exist | The backend bucket must be created before `init` (see Prerequisites). |
| `Unsupported argument "use_lockfile"` | Terraform is older than 1.10. Upgrade it. |
| `Invalid value for "path" parameter: no file exists at ~/.ssh/id_rsa.pub` | No SSH key yet. Run `ssh-keygen` as shown above. |
| `InvalidKeyPair.Duplicate: The keypair 'student-key' already exists` | A key pair with that name exists from an earlier run. Delete it in the EC2 console or run `terraform import aws_key_pair.student_key student-key`. |
| `BucketAlreadyExists` on `my-tf-test-bucket1120027788` | S3 bucket names are globally unique. Change the name in `S3bucket.tf`. |
| `OptInRequired` / `AuthFailure` in ap-south-2 | Enable the Hyderabad region in AWS Account → Regions. |
| `Error acquiring the state lock` | Another run is in progress or one crashed. If you are sure nothing else is running: `terraform force-unlock <LOCK_ID>`. |
| `ssh: Connection timed out` | Check the instance has a public IP, `demo-sg` is attached, and you are using user `ubuntu`. |
| `Permission denied (publickey)` | Use the private key that matches `~/.ssh/id_rsa.pub`: `ssh -i ~/.ssh/id_rsa ubuntu@<ip>`. |

---

## Known limitations

I found these while reviewing the code. They are the next things to fix.

1. **The EC2 instance and security group are not placed in the new VPC.** `aws_instance` has no `subnet_id`, and `aws_security_group` has no `vpc_id`, so both are created in the account's **default VPC**. The custom VPC is created but nothing runs in it.
2. **SSH is open to the whole internet** (`0.0.0.0/0` on port 22). It should be limited to my own IP.
3. **`enable_vpn_gateway = true`** creates a VPN gateway that nothing uses.
4. **The VPC module version is not pinned**, so a future `terraform init` could download a newer major version with breaking changes.
5. **No outputs** for the instance IP, VPC ID or subnet IDs.
6. The S3 bucket name and region are hardcoded instead of being variables.

## Next steps

- [ ] Put the instance in a public subnet: `subnet_id = module.vpc.public_subnets[0]`. Put the SG in the VPC: `vpc_id = module.vpc.vpc_id`.
- [ ] Restrict SSH with a `my_ip` variable (`cidr_blocks = [var.my_ip]`).
- [ ] Pin the module: `version = "~> 6.0"`. Check the registry for the current major version first.
- [ ] Remove `enable_vpn_gateway`.
- [ ] Add `outputs.tf` (instance public IP, VPC ID, subnet IDs).
- [ ] Add `required_version = ">= 1.10"` to the `terraform {}` block.
- [ ] Turn on S3 bucket versioning and block public access for the demo bucket.
- [ ] Run `terraform fmt -check` and `terraform validate` in CI with GitHub Actions.
