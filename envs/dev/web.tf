
module "web_stack" {
  source = "../../../terraform-aws-web-stack"

  project_name          = "novasphere"
  environment           = var.environment
  aws_region            = var.aws_region
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.public_subnets
  ami_id                = data.aws_ami.debian.id
  instance_type         = var.instance_type
  instance_profile_name = var.instance_profile_name
  ssm_parameter_name    = aws_ssm_parameter.db_password.name
  desired_capacity      = 2

  depends_on = [
    aws_ssm_parameter.db_password
  ]
}
