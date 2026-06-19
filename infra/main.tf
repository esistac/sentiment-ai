terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.0.0"
    }
  }
}

provider "docker" {
  # Connexion HTTP explicite requise pour l'environnement Jenkins local
  host = "http://host.docker.internal:2375"
}

# Déclaration de la variable reçue depuis le Jenkinsfile
variable "image_tag" {
  type        = string
  description = "Tag de l'image Docker à déployer"
}

# Import du réseau existant (cicd-network)
resource "docker_network" "cicd" {
  name = "cicd-network"
}

# Récupération de l'image déjà buildée par Jenkins (sans la re-compiler !)
resource "docker_image" "sentiment" {
  name         = "sentiment-ai:${var.image_tag}"
  keep_locally = true
}

# Déploiement du conteneur de staging
resource "docker_container" "sentiment_staging" {
  name    = "sentiment-staging"
  image   = docker_image.sentiment.image_id
  restart = "unless-stopped"

  ports {
    internal = 8000
    external = 8001
  }

  networks_advanced {
    name = docker_network.cicd.name
  }

  env = [
    "ENV=staging",
    "LOG_LEVEL=INFO"
  ]

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://localhost:8000/health"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "0s"
  }
}

# Variables de sortie (Outputs)
output "container_id" {
  value       = docker_container.sentiment_staging.id
  description = "ID du conteneur déployé"
}