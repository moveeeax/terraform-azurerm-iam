locals {
  # Built-in roles that hand out full control of the scope, or the ability to
  # grant oneself full control. Compared lower-cased.
  privileged_role_names = [
    "owner",
    "contributor",
    "user access administrator",
    "role based access control administrator",
  ]

  # Well-known built-in role definition GUIDs for the roles above. Without
  # these the gate below would be trivially bypassed by passing
  # role_definition_id instead of role_definition_name.
  privileged_role_guids = [
    "8e3af657-a8ff-443c-a75c-2fe8c4bcb635", # Owner
    "b24988ac-6180-42a0-ab88-20f7382dd24c", # Contributor
    "18d7d88d-d35e-4fb5-a5c3-7773c20a72d9", # User Access Administrator
    "f58310d9-a9f6-439a-9e8d-f62e7b41a168", # Role Based Access Control Administrator
  ]

  privileged_assignment_keys = sort([
    for k, v in var.role_assignments : k
    if contains(local.privileged_role_names, lower(v.role_definition_name == null ? "" : v.role_definition_name))
    || anytrue([
      for guid in local.privileged_role_guids :
      strcontains(lower(v.role_definition_id == null ? "" : v.role_definition_id), guid)
    ])
  ])

  # The privileged roles whose extra power is writing role assignments. An ABAC
  # condition on Microsoft.Authorization/roleAssignments actions can narrow
  # these to "may only hand out roles X and Y", which is how Microsoft
  # recommends delegating them. Contributor is left out on purpose: it cannot
  # write role assignments, so no delegation condition makes it any narrower.
  delegation_role_names = [
    "owner",
    "user access administrator",
    "role based access control administrator",
  ]

  delegation_role_guids = [
    "8e3af657-a8ff-443c-a75c-2fe8c4bcb635", # Owner
    "18d7d88d-d35e-4fb5-a5c3-7773c20a72d9", # User Access Administrator
    "f58310d9-a9f6-439a-9e8d-f62e7b41a168", # Role Based Access Control Administrator
  ]

  delegation_assignment_keys = sort([
    for k, v in var.role_assignments : k
    if contains(local.delegation_role_names, lower(v.role_definition_name == null ? "" : v.role_definition_name))
    || anytrue([
      for guid in local.delegation_role_guids :
      strcontains(lower(v.role_definition_id == null ? "" : v.role_definition_id), guid)
    ])
  ])

  # Delegation-role assignments whose condition mentions roleAssignments
  # actions. This is a substring check, not a parser: it proves the condition
  # is aimed at role assignment writes, not that it is tight.
  conditioned_delegation_keys = sort([
    for k in local.delegation_assignment_keys : k
    if strcontains(lower(var.role_assignments[k].condition == null ? "" : var.role_assignments[k].condition), "microsoft.authorization/roleassignments")
  ])

  # Actions that grant everything, or that let the holder grant themselves
  # everything. Matched case-insensitively against the requested actions.
  privileged_action_patterns = [
    "^\\*",                                              # "*", "*/read", "*/write" - every resource provider
    "^microsoft\\.authorization/\\*",                    # full control of RBAC
    "^microsoft\\.authorization/roleassignments/write$", # can grant itself any role
    "^microsoft\\.authorization/roledefinitions/write$", # can rewrite any role
  ]

  custom_role_actions = var.custom_role == null ? [] : concat(var.custom_role.actions, var.custom_role.data_actions)

  privileged_custom_role_actions = sort([
    for action in local.custom_role_actions : action
    if anytrue([for pattern in local.privileged_action_patterns : can(regex(pattern, lower(action)))])
  ])

  # RBAC at "/" applies to every subscription and management group in the
  # tenant, and a custom role defined there is assignable tenant-wide.
  scope_is_tenant_root = var.scope == "/"
}

resource "azurerm_role_definition" "this" {
  count = var.custom_role == null ? 0 : 1

  name  = var.custom_role.name
  scope = var.scope

  # The provider rejects an empty description outright ("expected description
  # to not be an empty string"), so an absent description must be null.
  description = var.custom_role.description == "" ? null : var.custom_role.description

  permissions {
    actions          = var.custom_role.actions
    not_actions      = var.custom_role.not_actions
    data_actions     = var.custom_role.data_actions
    not_data_actions = var.custom_role.not_data_actions
  }

  # Deliberately not configurable: the role is only ever assignable at the
  # scope it was defined at, never at "/" or a broader parent.
  assignable_scopes = [var.scope]

  lifecycle {
    precondition {
      condition     = var.allow_privileged_roles || length(local.privileged_custom_role_actions) == 0
      error_message = "custom_role \"${var.custom_role.name}\" requests ${join(", ", local.privileged_custom_role_actions)}, which is equivalent to Owner at ${var.scope}. List the specific actions the role needs, or set allow_privileged_roles = true to opt in."
    }

    precondition {
      condition     = var.allow_privileged_roles || !local.scope_is_tenant_root
      error_message = "custom_role \"${var.custom_role.name}\" would be defined at the tenant root scope \"/\", making it assignable across every subscription in the tenant. Use a narrower scope, or set allow_privileged_roles = true to opt in."
    }
  }
}

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  scope        = var.scope
  principal_id = each.value.principal_id

  # Supplying principal_type lets the provider skip the Entra ID lookup that
  # intermittently fails with PrincipalNotFound for a service principal
  # created in the same apply.
  principal_type                   = each.value.principal_type
  skip_service_principal_aad_check = each.value.skip_service_principal_aad_check

  role_definition_name = each.value.role_definition_name
  role_definition_id   = each.value.role_definition_id
  description          = each.value.description

  # condition_version only means something next to a condition, so it stays
  # null on unconditioned assignments and defaults to "2.0" otherwise.
  condition         = each.value.condition
  condition_version = each.value.condition == null ? null : coalesce(each.value.condition_version, "2.0")

  # A caller that creates the custom role here and then assigns it by name has
  # no expressible dependency between the two, so Terraform is free to attempt
  # the assignment before the definition exists.
  depends_on = [azurerm_role_definition.this]

  lifecycle {
    precondition {
      condition = (
        var.allow_privileged_roles
        || !contains(local.privileged_assignment_keys, each.key)
        || (var.privileged_requires_condition && contains(local.conditioned_delegation_keys, each.key))
      )
      error_message = "Role assignment \"${each.key}\" grants a privileged role (Owner, Contributor, User Access Administrator or Role Based Access Control Administrator) at ${var.scope}. Assign a narrower built-in role, set allow_privileged_roles = true to opt in, or (for Owner, User Access Administrator and Role Based Access Control Administrator) set privileged_requires_condition = true and add a condition that constrains Microsoft.Authorization/roleAssignments actions."
    }

    precondition {
      condition = (
        !var.privileged_requires_condition
        || !contains(local.delegation_assignment_keys, each.key)
        || contains(local.conditioned_delegation_keys, each.key)
      )
      error_message = "Role assignment \"${each.key}\" grants Owner, User Access Administrator or Role Based Access Control Administrator without a condition on Microsoft.Authorization/roleAssignments actions. privileged_requires_condition = true requires one, even when allow_privileged_roles = true."
    }

    precondition {
      condition     = var.allow_privileged_roles || !local.scope_is_tenant_root
      error_message = "Role assignment \"${each.key}\" targets the tenant root scope \"/\", which applies to every subscription and management group in the tenant. Use a narrower scope, or set allow_privileged_roles = true to opt in."
    }
  }
}
