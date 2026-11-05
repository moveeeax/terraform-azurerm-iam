config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.33.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# prevent_destroy cannot be parameterised, so a reusable module cannot set it
# without making the resource impossible to delete for every caller. Callers
# protect their data with their own lifecycle rules or resource locks.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}
