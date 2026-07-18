terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "scope" {
  description = "Scope (e.g. resource group ID) to assign roles at."
  type        = string
}

variable "principal_id" {
  description = "Object ID of the principal to grant access to."
  type        = string
}

module "iam" {
  source = "../.."

  scope = var.scope

  role_assignments = {
    "reader" = {
      principal_id         = var.principal_id
      role_definition_name = "Reader"
    }
  }

  custom_role = {
    name        = "example-storage-lister"
    description = "Can list storage accounts."
    actions     = ["Microsoft.Storage/storageAccounts/read"]
  }
}

output "role_assignment_ids" {
  value = module.iam.role_assignment_ids
}
