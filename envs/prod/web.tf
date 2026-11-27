
module "web_stack" {
  #checkov:skip=CKV_TF_1:Version figee par tag, voir SECURITE.md section 3
  source = "git::https://github.com/ebonnard91/terraform-aws-web-stack.git?ref=v1.0.0"

  project_name          = "novasphere"
  environment           = var.environment
  aws_region            = var.aws_region
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.public_subnets
  ami_id                = data.aws_ami.debian.id
  instance_type         = var.instance_type
  instance_profile_name = var.instance_profile_name
  ssm_parameter_name    = aws_ssm_parameter.db_password.name
  domain_name           = var.domain_name
  desired_capacity      = var.desired_capacity

  depends_on = [
    aws_ssm_parameter.db_password
  ]
}
