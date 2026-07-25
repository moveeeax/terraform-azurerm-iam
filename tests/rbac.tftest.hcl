# Test-suite only: `mock_provider` requires Terraform >= 1.7. The module itself
# still supports >= 1.5 (see versions.tf) — do not raise required_version for
# the sake of these tests.

mock_provider "azurerm" {}

variables {
  scope = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg"
}

run "no_grants_by_default" {
  command = plan

  assert {
    condition     = length(output.role_assignment_ids) == 0
    error_message = "The module must not create any role assignment unless one is asked for."
  }

  assert {
    condition     = output.custom_role_definition_id == null
    error_message = "The module must not create a custom role unless one is asked for."
  }
}

run "custom_role_is_assignable_only_at_its_own_scope" {
  command = plan

  variables {
    custom_role = {
      name    = "storage-lister"
      actions = ["Microsoft.Storage/storageAccounts/read"]
    }
  }

  assert {
    condition     = one(azurerm_role_definition.this[0].assignable_scopes) == var.scope
    error_message = "assignable_scopes must be exactly the module scope, never broader."
  }
}

run "principal_type_is_passed_to_the_assignment" {
  command = plan

  variables {
    role_assignments = {
      app = {
        principal_id         = "11111111-1111-1111-1111-111111111111"
        principal_type       = "ServicePrincipal"
        role_definition_name = "Reader"
      }
    }
  }

  assert {
    condition     = azurerm_role_assignment.this["app"].principal_type == "ServicePrincipal"
    error_message = "principal_type must reach the provider; without it a freshly created service principal fails with PrincipalNotFound."
  }
}

# --- privileged built-in roles are gated ------------------------------------

run "rejects_owner_by_name" {
  command = plan

  variables {
    role_assignments = {
      admin = {
        principal_id         = "11111111-1111-1111-1111-111111111111"
        role_definition_name = "Owner"
      }
    }
  }

  expect_failures = [azurerm_role_assignment.this]
}

run "rejects_contributor_by_role_definition_id" {
  command = plan

  variables {
    role_assignments = {
      admin = {
        principal_id       = "11111111-1111-1111-1111-111111111111"
        role_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
      }
    }
  }

  expect_failures = [azurerm_role_assignment.this]
}

run "allows_owner_when_explicitly_opted_in" {
  command = plan

  variables {
    allow_privileged_roles = true
    role_assignments = {
      admin = {
        principal_id         = "11111111-1111-1111-1111-111111111111"
        role_definition_name = "Owner"
      }
    }
  }

  assert {
    condition     = azurerm_role_assignment.this["admin"].role_definition_name == "Owner"
    error_message = "allow_privileged_roles = true must permit an Owner assignment."
  }
}

run "allows_non_privileged_roles_without_opt_in" {
  command = plan

  variables {
    role_assignments = {
      reader = {
        principal_id         = "11111111-1111-1111-1111-111111111111"
        role_definition_name = "Reader"
      }
    }
  }

  assert {
    condition     = azurerm_role_assignment.this["reader"].role_definition_name == "Reader"
    error_message = "Non-privileged built-in roles must not require an opt-in."
  }
}

# --- wildcard custom roles are gated ----------------------------------------

run "rejects_wildcard_custom_role_actions" {
  command = plan

  variables {
    custom_role = {
      name    = "everything"
      actions = ["*"]
    }
  }

  expect_failures = [azurerm_role_definition.this]
}

run "rejects_custom_role_that_can_grant_itself_any_role" {
  command = plan

  variables {
    custom_role = {
      name    = "escalator"
      actions = ["Microsoft.Authorization/roleAssignments/write"]
    }
  }

  expect_failures = [azurerm_role_definition.this]
}

run "allows_wildcard_custom_role_when_explicitly_opted_in" {
  command = plan

  variables {
    allow_privileged_roles = true
    custom_role = {
      name    = "everything"
      actions = ["*"]
    }
  }

  assert {
    condition     = contains(azurerm_role_definition.this[0].permissions[0].actions, "*")
    error_message = "allow_privileged_roles = true must permit a wildcard custom role."
  }
}

# --- tenant root scope is gated ---------------------------------------------

run "rejects_tenant_root_scope" {
  command = plan

  variables {
    scope = "/"
    role_assignments = {
      reader = {
        principal_id         = "11111111-1111-1111-1111-111111111111"
        role_definition_name = "Reader"
      }
    }
  }

  expect_failures = [azurerm_role_assignment.this]
}

# --- input validation -------------------------------------------------------

run "rejects_scope_that_is_not_a_resource_id" {
  command = plan

  variables {
    scope = "prod-rg"
  }

  expect_failures = [var.scope]
}

run "rejects_assignment_with_no_role_definition" {
  command = plan

  variables {
    role_assignments = {
      broken = {
        principal_id = "11111111-1111-1111-1111-111111111111"
      }
    }
  }

  expect_failures = [var.role_assignments]
}

run "rejects_assignment_with_both_role_definition_name_and_id" {
  command = plan

  variables {
    role_assignments = {
      broken = {
        principal_id         = "11111111-1111-1111-1111-111111111111"
        role_definition_name = "Reader"
        role_definition_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
      }
    }
  }

  expect_failures = [var.role_assignments]
}

run "rejects_invalid_principal_type" {
  command = plan

  variables {
    role_assignments = {
      broken = {
        principal_id         = "11111111-1111-1111-1111-111111111111"
        principal_type       = "serviceprincipal"
        role_definition_name = "Reader"
      }
    }
  }

  expect_failures = [var.role_assignments]
}

run "rejects_custom_role_with_no_permissions" {
  command = plan

  variables {
    custom_role = {
      name = "does-nothing"
    }
  }

  expect_failures = [var.custom_role]
}
