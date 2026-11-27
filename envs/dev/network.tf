module "vpc" {
  #checkov:skip=CKV_TF_1:Version exacte du registry, voir SECURITE.md section 3
  #checkov:skip=CKV2_AWS_12:Faux positif, SG par defaut adopte par le module sans aucune regle (lignes default_security_group ci-dessous), voir SECURITE.md section 3
  #checkov:skip=CKV_AWS_130:Pas de NAT Gateway, IP publique requise pour SSM et les depots ; entrees limitees a l'ALB par le SG web, voir SECURITE.md section 3
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.8.0"

  name = "novasphere-${var.environment}"
  cidr = "10.0.0.0/16"

  azs            = ["us-east-1a", "us-east-1b"]
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway      = false
  map_public_ip_on_launch = true

  # SG par defaut du VPC adopte et vide : aucune entree, aucune sortie.
  # Valeurs par defaut du module, ecrites ici pour rendre la regle visible.
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []
}
