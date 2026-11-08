variable "scope" {
  description = "Scope at which role assignments and any custom role definition apply (e.g. a subscription, resource group, or resource ID)."
  type        = string

  validation {
    condition = can(regex(
      "^(/|/subscriptions/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(/.+)?|/providers/Microsoft\\.Management/managementGroups/.+)$",
      var.scope
    ))
    error_message = "scope must be a fully qualified Azure scope ID: \"/\" (tenant root), \"/subscriptions/<subscription-id>[/...]\", or \"/providers/Microsoft.Management/managementGroups/<name>\". A bare resource group or subscription name is not a scope."
  }
}

variable "role_assignments" {
  description = <<-EOT
    Map of role assignments to create, keyed by an arbitrary identifier.

    Set exactly one of `role_definition_name` (a built-in role) or
    `role_definition_id` (a custom or otherwise known role definition).

    Set `principal_type` when it is known. For a service principal created in
    the same apply, `principal_type = "ServicePrincipal"` (or
    `skip_service_principal_aad_check = true`) avoids the intermittent
    "PrincipalNotFound" failure caused by Entra ID replication lag.

    `condition` is an Azure ABAC condition expression that narrows what the
    assignment allows. `condition_version` defaults to "2.0" when a condition
    is set and must be left null otherwise.
  EOT

  type = map(object({
    principal_id                     = string
    principal_type                   = optional(string, null)
    role_definition_name             = optional(string, null)
    role_definition_id               = optional(string, null)
    description                      = optional(string, null)
    skip_service_principal_aad_check = optional(bool, null)
    condition                        = optional(string, null)
    condition_version                = optional(string, null)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.role_assignments :
      (v.role_definition_name == null) != (v.role_definition_id == null)
    ])
    error_message = "Each role assignment must set exactly one of role_definition_name or role_definition_id — not both, and not neither."
  }

  validation {
    condition = alltrue([
      for k, v in var.role_assignments :
      v.principal_type == null || contains(["User", "Group", "ServicePrincipal"], coalesce(v.principal_type, "User"))
    ])
    error_message = "principal_type must be one of \"User\", \"Group\" or \"ServicePrincipal\" (case sensitive), or null to let Azure resolve it."
  }

  validation {
    condition = alltrue([
      for k, v in var.role_assignments : trimspace(v.principal_id) != ""
    ])
    error_message = "principal_id must be a non-empty object ID."
  }

  validation {
    condition = alltrue([
      for k, v in var.role_assignments : v.condition == null || trimspace(coalesce(v.condition, " ")) != ""
    ])
    error_message = "condition must be a non-empty ABAC expression, or null for an unconditioned assignment."
  }

  validation {
    condition = alltrue([
      for k, v in var.role_assignments : v.condition_version == null || v.condition != null
    ])
    error_message = "condition_version is only valid together with condition."
  }
}

variable "custom_role" {
  description = "Optional custom role definition to create at the scope. Its assignable_scopes is always exactly `scope`, so the role can never be used anywhere broader. Null disables custom role creation."
  type = object({
    name             = string
    description      = optional(string, null)
    actions          = optional(list(string), [])
    not_actions      = optional(list(string), [])
    data_actions     = optional(list(string), [])
    not_data_actions = optional(list(string), [])
  })
  default = null

  validation {
    condition     = var.custom_role == null || length(try(var.custom_role.actions, [])) + length(try(var.custom_role.data_actions, [])) > 0
    error_message = "custom_role must grant at least one action or data_action; a role definition with no permissions is never useful."
  }

  validation {
    condition     = var.custom_role == null || trimspace(try(var.custom_role.name, "")) != ""
    error_message = "custom_role.name must be a non-empty string."
  }
}

variable "allow_privileged_roles" {
  description = <<-EOT
    Opt in to grants that confer full control of the scope. Left at false, the
    module refuses to plan:

      * assignments of Owner, Contributor, User Access Administrator or
        Role Based Access Control Administrator (matched by name or by
        well-known built-in role definition ID);
      * custom roles with wildcard actions, or with the RBAC write actions
        that let the holder grant themselves anything;
      * any grant at the tenant root scope ("/").

    Set to true only when a broad grant is genuinely intended.
  EOT

  type    = bool
  default = false
}

variable "privileged_requires_condition" {
  description = <<-EOT
    Opt in to conditioned delegation of the role-assigning roles. When true:

      * an assignment of Owner, User Access Administrator or Role Based Access
        Control Administrator passes the privileged-role gate without
        allow_privileged_roles, provided its `condition` constrains
        Microsoft.Authorization/roleAssignments actions;
      * the same roles without such a condition are rejected, even when
        allow_privileged_roles = true.

    Contributor, wildcard custom roles and the tenant root scope are not
    affected and still need allow_privileged_roles.
  EOT

  type    = bool
  default = false
}
