terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # 3.87.0 is the first release in which `principal_type` on
      # azurerm_role_assignment is a settable argument. Up to and including
      # 3.86.0 it is read-only and Terraform rejects the configuration with
      # "Value for unconfigurable attribute". Verified by pinning each build.
      version = ">= 3.87, < 5.0"
    }
  }
}
