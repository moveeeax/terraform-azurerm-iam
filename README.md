# terraform-azurerm-iam

Terraform module that manages [Azure](https://azure.microsoft.com/) role-based
access control (RBAC). It creates a set of role assignments at a given scope
from an input map and, optionally, a single custom role definition scoped to
the same location.

## Usage

```hcl
module "iam" {
  source = "github.com/cybercapybara/terraform-azurerm-iam"

  scope = "/subscriptions/xxxx/resourceGroups/prod-rg"

  role_assignments = {
    "app-reader" = {
      principal_id         = "00000000-0000-0000-0000-000000000000"
      role_definition_name = "Reader"
    }
  }
}
```

A runnable example lives in [`examples/basic`](examples/basic).

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5   |
| azurerm   | >= 3.0   |

## Inputs

| Name               | Description                                                                 | Type          | Default | Required |
|--------------------|-----------------------------------------------------------------------------|---------------|---------|:--------:|
| `scope`            | Scope at which assignments and any custom role apply.                        | `string`      | n/a     |   yes    |
| `role_assignments` | Map of role assignments keyed by an arbitrary identifier.                    | `map(object)` | `{}`    |    no    |
| `custom_role`      | Optional custom role definition to create at the scope.                      | `object`      | `null`  |    no    |

## Outputs

| Name                        | Description                                     |
|-----------------------------|-------------------------------------------------|
| `role_assignment_ids`       | Map of role assignment keys to their IDs.       |
| `custom_role_definition_id` | ID of the custom role definition, if created.   |

## License

[MIT](LICENSE)
