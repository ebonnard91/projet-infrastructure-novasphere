
variable "aws_region" {
  description = "Region AWS de deploiement"
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Trigramme de l'etudiant"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{3}$", var.owner))
    error_message = "Le trigramme doit contenir 3 lettres minuscules."
  }
}

variable "environment" {
  description = "Environnement de deploiement"
  type        = string

  validation {
    condition     = var.environment == "prod"
    error_message = "Cet environnement doit etre prod."
  }
}

variable "instance_type" {
  description = "Type des instances EC2"
  type        = string
  default     = "t3.small"
}

variable "instance_profile_name" {
  description = "Profil IAM des instances EC2"
  type        = string
  default     = "LabInstanceProfile"
}

variable "desired_capacity" {
  description = "Nombre d'instances EC2 souhaite"
  type        = number
  default     = 2

  validation {
    condition     = var.desired_capacity >= 2 && var.desired_capacity <= 4
    error_message = "La capacite doit etre comprise entre 2 et 4."
  }
}
