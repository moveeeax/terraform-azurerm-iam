resource "azurerm_role_definition" "this" {
  count = var.custom_role == null ? 0 : 1

  name        = var.custom_role.name
  scope       = var.scope
  description = var.custom_role.description

  permissions {
    actions          = var.custom_role.actions
    not_actions      = var.custom_role.not_actions
    data_actions     = var.custom_role.data_actions
    not_data_actions = var.custom_role.not_data_actions
  }

  assignable_scopes = [var.scope]
}

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  scope                = var.scope
  principal_id         = each.value.principal_id
  role_definition_name = each.value.role_definition_name
  role_definition_id   = each.value.role_definition_id
  description          = each.value.description
}
