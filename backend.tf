terraform {
  backend "s3" {
    bucket       = "backend-state-1122"
    key          = "terraform/terraform.tfstate"
    region       = "ap-south-2"
    use_lockfile = true
  }
}
