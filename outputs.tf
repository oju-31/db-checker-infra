output "application_url" {
  description = "HTTP URL for the PHP application."
  value       = module.infra.application_url
}

output "alb_dns_name" {
  description = "DNS name of the public Application Load Balancer."
  value       = module.infra.alb_dns_name
}
