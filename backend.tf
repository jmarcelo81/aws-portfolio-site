terraform {
  backend "s3" {
    bucket = "jmarcelo-portfolio-tfstate"
    key    = "EC2_prod/terraform.tfstate"
    region = "us-east-1"
  }
}
