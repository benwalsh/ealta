data "aws_caller_identity" "current" {}

# Use the account's default VPC + subnets — enough for one small service + a
# private RDS. (Swap for a dedicated VPC module later if you want isolation.)
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
