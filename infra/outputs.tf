output "container_id" {
  description = "ID du conteneur staging"
  value       = docker_container.sentiment_staging.id
}

output "app_url" {
  description = "URL de l'application staging"
  value       = "http://localhost:${var.app_port}"
}

output "network_name" {
  description = "Nom du reseau Docker utilise"
  # CORRECTION : On utilise data.docker_network au lieu de docker_network
  value       = data.docker_network.cicd.name
}