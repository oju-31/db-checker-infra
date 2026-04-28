variable "ENV" {
  type = string
}

variable "COMMON_TAGS" {
  type = map(string)
}

variable "RESOURCE_PREFIX" {
  type = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "app_image" {
  type    = string
  default = "ghcr.io/korohandelsgmbh/coding-test-2025:latest"
}

variable "app_desired_count" {
  type    = number
  default = 3
}

variable "app_container_port" {
  type    = number
  default = 80
}

variable "mysql_image" {
  type    = string
  default = "mysql:8"
}

variable "redis_image" {
  type    = string
  default = "redis:7"
}

variable "database_name" {
  type    = string
  default = "visits"
}

variable "database_user" {
  type    = string
  default = "visit_logger"
}

variable "database_password" {
  type    = string
  default = "visit_logger_password"
}

variable "database_root_password" {
  type    = string
  default = "root_password"
}
