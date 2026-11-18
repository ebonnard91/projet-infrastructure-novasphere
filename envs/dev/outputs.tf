
output "alb_dns_name" {
  description = "Adresse DNS du Load Balancer DEV"
  value       = module.web_stack.alb_dns_name
}

output "application_url" {
  description = "URL de l'application NovaSphere DEV"
  value       = "http://${module.web_stack.alb_dns_name}"
}

output "target_group_arn" {
  description = "ARN du Target Group"
  value       = module.web_stack.target_group_arn
}

output "autoscaling_group_name" {
  description = "Nom de l'Auto Scaling Group"
  value       = module.web_stack.autoscaling_group_name
}
