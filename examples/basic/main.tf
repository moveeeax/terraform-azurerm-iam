terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.87, < 6.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "scope" {
  description = "Scope to assign roles at, as a full resource ID (e.g. /subscriptions/<id>/resourceGroups/prod-rg). Prefer the narrowest scope that works."
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

      # Naming the principal type avoids the intermittent PrincipalNotFound
      # error when the service principal was created in the same apply.
      principal_type = "ServicePrincipal"
    }
  }

  custom_role = {
    name        = "example-storage-lister"
    description = "Can list storage accounts."
    actions     = ["Microsoft.Storage/storageAccounts/read"]
  }

  # Left at its default of false. Assigning Owner/Contributor, defining a
  # wildcard custom role, or working at the tenant root scope all require
  # setting this to true explicitly.
  allow_privileged_roles = false
}

output "role_assignment_ids" {
  value = module.iam.role_assignment_ids
}

output "custom_role_definition_id" {
  value = module.iam.custom_role_definition_id
}
