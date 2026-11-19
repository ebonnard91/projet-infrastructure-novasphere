output "alb_dns_name" {
  description = "Adresse DNS du Load Balancer PROD (cible du CNAME app.aero-nex.fr)"
  value       = module.web_stack.alb_dns_name
}

output "application_url" {
  description = "URL de l'application NovaSphere PROD"
  value       = "https://${var.domain_name}"
}

output "acm_validation_records" {
  description = "CNAME a creer chez le registrar pour valider le certificat ACM"
  value       = module.web_stack.acm_validation_records
}
