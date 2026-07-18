output "role_assignment_ids" {
  description = "Map of role assignment keys to their IDs."
  value       = { for k, v in azurerm_role_assignment.this : k => v.id }
}

output "custom_role_definition_id" {
  description = "ID of the custom role definition, if one was created."
  value       = try(azurerm_role_definition.this[0].role_definition_resource_id, null)
}
