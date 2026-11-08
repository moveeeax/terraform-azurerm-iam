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

# --- ABAC conditions ----------------------------------------------------------

run "unconditioned_assignment_plans_as_before" {
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
    condition     = azurerm_role_assignment.this["reader"].condition == null
    error_message = "An assignment without a condition must not get one."
  }

  # condition_version is Optional+Computed on azurerm 4.x and later, so the mock
  # provider fills in a random value when the module passes null. It cannot be
  # asserted here; main.tf sets it to null whenever condition is null.
}

run "condition_is_passed_with_default_version" {
  command = plan

  variables {
    role_assignments = {
      blob = {
        principal_id         = "11111111-1111-1111-1111-111111111111"
        role_definition_name = "Storage Blob Data Reader"
        condition            = "((!(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'})) OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringEquals 'logs'))"
      }
    }
  }

  assert {
    condition     = strcontains(azurerm_role_assignment.this["blob"].condition, "StringEquals 'logs'")
    error_message = "condition must reach the provider unchanged."
  }

  assert {
    condition     = azurerm_role_assignment.this["blob"].condition_version == "2.0"
    error_message = "condition_version must default to 2.0 when a condition is set."
  }
}

run "rejects_condition_version_without_condition" {
  command = plan

  variables {
    role_assignments = {
      broken = {
        principal_id         = "11111111-1111-1111-1111-111111111111"
        role_definition_name = "Reader"
        condition_version    = "2.0"
      }
    }
  }

  expect_failures = [var.role_assignments]
}

run "rejects_empty_condition" {
  command = plan

  variables {
    role_assignments = {
      broken = {
        principal_id         = "11111111-1111-1111-1111-111111111111"
        role_definition_name = "Reader"
        condition            = "  "
      }
    }
  }

  expect_failures = [var.role_assignments]
}

run "conditioned_uaa_is_still_gated_without_opt_in" {
  command = plan

  variables {
    role_assignments = {
      delegate = {
        principal_id         = "11111111-1111-1111-1111-111111111111"
        role_definition_name = "User Access Administrator"
        condition            = "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {acdd72a7-3385-48ef-bd42-f606fba81ae7}))"
      }
    }
  }

  expect_failures = [azurerm_role_assignment.this]
}

run "allows_conditioned_uaa_with_privileged_requires_condition" {
  command = plan

  variables {
    privileged_requires_condition = true
    role_assignments = {
      delegate = {
        principal_id         = "11111111-1111-1111-1111-111111111111"
        role_definition_name = "User Access Administrator"
        condition            = "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {acdd72a7-3385-48ef-bd42-f606fba81ae7}))"
      }
    }
  }

  assert {
    condition     = azurerm_role_assignment.this["delegate"].condition_version == "2.0"
    error_message = "A conditioned User Access Administrator assignment must plan when privileged_requires_condition = true."
  }
}

run "allows_conditioned_rbac_admin_by_role_definition_id" {
  command = plan

  variables {
    privileged_requires_condition = true
    role_assignments = {
      delegate = {
        principal_id       = "11111111-1111-1111-1111-111111111111"
        role_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/f58310d9-a9f6-439a-9e8d-f62e7b41a168"
        condition          = "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {acdd72a7-3385-48ef-bd42-f606fba81ae7}))"
      }
    }
  }

  assert {
    condition     = length(output.role_assignment_ids) == 1
    error_message = "The delegation gate must match role_definition_id as well as role_definition_name."
  }
}

run "rejects_unconditioned_uaa_when_condition_required" {
  command = plan

  variables {
    allow_privileged_roles        = true
    privileged_requires_condition = true
    role_assignments = {
      delegate = {
        principal_id         = "11111111-1111-1111-1111-111111111111"
        role_definition_name = "User Access Administrator"
      }
    }
  }

  expect_failures = [azurerm_role_assignment.this]
}

run "rejects_uaa_whose_condition_ignores_role_assignments" {
  command = plan

  variables {
    privileged_requires_condition = true
    role_assignments = {
      delegate = {
        principal_id         = "11111111-1111-1111-1111-111111111111"
        role_definition_name = "User Access Administrator"
        condition            = "((!(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'})) OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringEquals 'logs'))"
      }
    }
  }

  expect_failures = [azurerm_role_assignment.this]
}

run "conditioned_contributor_still_needs_allow_privileged_roles" {
  command = plan

  variables {
    privileged_requires_condition = true
    role_assignments = {
      admin = {
        principal_id         = "11111111-1111-1111-1111-111111111111"
        role_definition_name = "Contributor"
        condition            = "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {acdd72a7-3385-48ef-bd42-f606fba81ae7}))"
      }
    }
  }

  expect_failures = [azurerm_role_assignment.this]
}
