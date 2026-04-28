locals {
  RESOURCE_PREFIX = "${var.ENV}-db-checker"

  COMMON_TAGS = {
    Environment = var.ENV
    Application = "db-caller"
    Project     = "technical-interview-KH"
    Owner       = "aojutomori@gmail.com"
    CostCenter  = "Templated-tutorial${var.ENV}-001"
  }
}


###########################################
# INFRA MODULE
###########################################
module "infra" {
  source          = "./infra"
  ENV             = var.ENV
  COMMON_TAGS     = local.COMMON_TAGS
  RESOURCE_PREFIX = local.RESOURCE_PREFIX
}
