# terraform-azurerm-iam

Terraform module that manages [Azure](https://azure.microsoft.com/) role-based
access control (RBAC). It creates a set of role assignments at a given scope
from an input map and, optionally, a single custom role definition scoped to
the same location.

## Usage

```hcl
module "iam" {
  source = "github.com/moveeeax/terraform-azurerm-iam?ref=v1.0.0"

  scope = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-rg"

  role_assignments = {
    "app-reader" = {
      principal_id         = "11111111-1111-1111-1111-111111111111"
      principal_type       = "ServicePrincipal"
      role_definition_name = "Reader"
    }
  }
}
```

A runnable example lives in [`examples/basic`](examples/basic).

## Safe by default

The module refuses to plan a grant that hands out full control of the scope
unless you say so explicitly with `allow_privileged_roles = true`. Gated:

* assignments of **Owner**, **Contributor**, **User Access Administrator** or
  **Role Based Access Control Administrator** — matched both by
  `role_definition_name` and by the well-known built-in role definition GUID,
  so the gate cannot be sidestepped by switching to `role_definition_id`;
* custom roles with wildcard actions (`*`, `*/write`,
  `Microsoft.Authorization/*`) or with the RBAC write actions that let the
  holder grant themselves anything;
* any grant at the tenant root scope (`/`), which reaches every subscription
  and management group in the tenant.

A custom role's `assignable_scopes` is always exactly `scope` and is not
configurable, so a role defined here can never be assigned somewhere broader
than where it was created.

Prefer the narrowest scope that works: a resource group ID rather than a
subscription ID, a resource ID rather than a resource group.

### Conditions (ABAC)

Each assignment accepts an Azure ABAC `condition`. `condition_version`
defaults to `"2.0"` when a condition is set and stays null otherwise, so
existing assignments plan unchanged.

```hcl
role_assignments = {
  "logs-reader" = {
    principal_id         = "11111111-1111-1111-1111-111111111111"
    role_definition_name = "Storage Blob Data Reader"
    condition            = "((!(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'})) OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringEquals 'logs'))"
  }
}
```

To delegate role assignment management, which is what Microsoft recommends
instead of a plain User Access Administrator grant, set
`privileged_requires_condition = true` (recommended whenever you delegate).
Then an assignment of Owner, User Access Administrator or Role Based Access
Control Administrator passes the gate without `allow_privileged_roles` if its
condition constrains `Microsoft.Authorization/roleAssignments` actions, and the
same roles without such a condition are rejected even with
`allow_privileged_roles = true`.

```hcl
privileged_requires_condition = true

role_assignments = {
  "team-lead-can-grant-reader" = {
    principal_id         = "11111111-1111-1111-1111-111111111111"
    role_definition_name = "Role Based Access Control Administrator"
    # May only assign Reader (acdd72a7-...).
    condition = "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {acdd72a7-3385-48ef-bd42-f606fba81ae7}))"
  }
}
```

The check is a substring match on the condition text: it confirms the
condition targets role assignment actions, not that it is narrow. Review the
expression itself. Contributor, wildcard custom roles and the tenant root scope
are not affected and still need `allow_privileged_roles`.

### Service principal replication lag

Set `principal_type` on each assignment when you know it. Azure RBAC creation
against a service principal that was created moments earlier intermittently
fails with `PrincipalNotFound` because of Entra ID replication lag; naming the
type lets the provider skip the directory lookup. `skip_service_principal_aad_check`
is available as an explicit escape hatch for the same problem.

## Requirements

| Name      | Version           |
|-----------|-------------------|
| terraform | >= 1.5            |
| azurerm   | >= 3.87, < 6.0    |

`principal_type` on `azurerm_role_assignment` only became a settable argument
in azurerm **3.87.0**; on 3.86.0 and earlier it is read-only and the
configuration is rejected outright. Running the test suite additionally needs
Terraform >= 1.7 for `mock_provider`. CI runs against the latest azurerm 5.x
release; 6.x is excluded until it has been tested.

## Inputs

| Name                     | Description                                                                       | Type          | Default | Required |
|--------------------------|-----------------------------------------------------------------------------------|---------------|---------|:--------:|
| `scope`                  | Scope at which assignments and any custom role apply. Must be a full Azure scope ID. | `string`      | n/a     |   yes    |
| `role_assignments`       | Map of role assignments keyed by an arbitrary identifier.                          | `map(object)` | `{}`    |    no    |
| `custom_role`            | Optional custom role definition to create at the scope.                            | `object`      | `null`  |    no    |
| `allow_privileged_roles` | Opt in to grants that confer full control of the scope (see above).                | `bool`        | `false` |    no    |
| `privileged_requires_condition` | Let conditioned Owner, User Access Administrator and RBAC Administrator assignments pass the gate, and reject them unconditioned (see Conditions). | `bool` | `false` | no |

### `role_assignments` object

| Field                              | Type     | Default | Notes                                                              |
|------------------------------------|----------|---------|--------------------------------------------------------------------|
| `principal_id`                     | `string` | n/a     | Object ID of the user, group or service principal.                  |
| `principal_type`                   | `string` | `null`  | `User`, `Group` or `ServicePrincipal`.                              |
| `role_definition_name`             | `string` | `null`  | Built-in role name. Exactly one of this or `role_definition_id`.    |
| `role_definition_id`               | `string` | `null`  | Custom or known role definition ID.                                 |
| `description`                      | `string` | `null`  | Free-text justification stored on the assignment.                   |
| `skip_service_principal_aad_check` | `bool`   | `null`  | Skip the Entra ID lookup for a just-created service principal.       |
| `condition`                        | `string` | `null`  | ABAC condition expression. Must be non-empty when set.              |
| `condition_version`                | `string` | `null`  | Defaults to `"2.0"` when `condition` is set; only valid with it.    |

### `custom_role` object

| Field              | Type           | Default | Notes                                        |
|--------------------|----------------|---------|----------------------------------------------|
| `name`             | `string`       | n/a     | Role name, must be non-empty.                 |
| `description`      | `string`       | `null`  | Empty strings are rejected by Azure.          |
| `actions`          | `list(string)` | `[]`    | At least one action or data action required.  |
| `not_actions`      | `list(string)` | `[]`    |                                               |
| `data_actions`     | `list(string)` | `[]`    |                                               |
| `not_data_actions` | `list(string)` | `[]`    |                                               |

## Outputs

| Name                        | Description                                     |
|-----------------------------|-------------------------------------------------|
| `role_assignment_ids`       | Map of role assignment keys to their IDs.       |
| `custom_role_definition_id` | ID of the custom role definition, if created.   |

## Development

```sh
terraform fmt -recursive
terraform init -backend=false && terraform validate
terraform test          # mocked provider, no credentials and no network needed
tflint
```

## License

[MIT](LICENSE)
