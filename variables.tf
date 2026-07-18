variable "scope" {
  description = "Scope at which role assignments and any custom role definition apply (e.g. a subscription, resource group, or resource ID)."
  type        = string
}

variable "role_assignments" {
  description = "Map of role assignments to create, keyed by an arbitrary identifier. Set role_definition_name for a built-in role or role_definition_id for a custom/known role."
  type = map(object({
    principal_id         = string
    role_definition_name = optional(string, null)
    role_definition_id   = optional(string, null)
    description          = optional(string, null)
  }))
  default = {}
}

variable "custom_role" {
  description = "Optional custom role definition to create at the scope. Null disables custom role creation."
  type = object({
    name             = string
    description      = optional(string, "")
    actions          = optional(list(string), [])
    not_actions      = optional(list(string), [])
    data_actions     = optional(list(string), [])
    not_data_actions = optional(list(string), [])
  })
  default = null
}
