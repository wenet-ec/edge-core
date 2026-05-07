# edge_admin/lib/edge_admin_web/schemas/nodes/alias_schemas.ex
defmodule EdgeAdminWeb.Schemas.Nodes.AliasSchemas do
  @moduledoc """
  OpenAPI schemas for Alias resources
  """

  use EdgeAdminWeb.Schema

  alias EdgeAdmin.Naming
  alias EdgeAdminWeb.Schemas.CommonSchemas
  alias OpenApiSpex.Schema

  defmodule AliasResponse do
    @moduledoc false

    schema(%{
      title: "AliasResponse",
      description: "Node alias with custom DNS entry",
      type: :object,
      properties: %{
        id: %Schema{
          type: :string,
          format: :uuid,
          description: "Unique alias identifier"
        },
        name: %Schema{
          type: :string,
          description: "Alias name (used in DNS)",
          pattern: Naming.alias_name_pattern(),
          example: "web-server"
        },
        vpn_hostname: %Schema{
          type: :string,
          description: "Full DNS hostname (FQDN)",
          example: "node-web-server.cluster-prod.nm.internal"
        },
        node_id: %Schema{
          type: :string,
          format: :uuid,
          description: "ID of the node this alias belongs to"
        },
        cluster_name: %Schema{
          type: :string,
          description: "Name of the cluster",
          example: "prod-east"
        },
        inserted_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "Timestamp when the alias was created"
        },
        updated_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "Timestamp when the alias was last updated"
        }
      },
      required: [:id, :name, :vpn_hostname, :node_id, :cluster_name],
      example: %{
        id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        name: "web-server",
        vpn_hostname: "node-web-server.cluster-prod.nm.internal",
        node_id: "01234567-89ab-cdef-0123-456789abcdef",
        cluster_name: "prod",
        inserted_at: "2024-01-15T10:30:00Z",
        updated_at: "2024-01-15T10:30:00Z"
      }
    })
  end

  defmodule AliasSingleResponse do
    @moduledoc false

    schema(CommonSchemas.single_response(AliasResponse, "AliasSingleResponse", "Single alias response"))
  end

  defmodule AliasPaginatedResponse do
    @moduledoc false

    schema(
      CommonSchemas.paginated_response(
        AliasResponse,
        "AliasPaginatedResponse",
        "Paginated list of aliases with filtering and sorting metadata"
      )
    )
  end

  defmodule CreateAliasRequest do
    @moduledoc false

    schema(%{
      title: "CreateAliasRequest",
      description: "Parameters for creating a new DNS alias for a node",
      type: :object,
      properties: %{
        name: %Schema{
          type: :string,
          pattern: Naming.alias_name_pattern(),
          minLength: Naming.alias_name_min_length(),
          maxLength: Naming.alias_name_max_length(),
          description: "Alias name (lowercase alphanumeric with hyphens)",
          example: "web-server"
        }
      },
      required: [:name],
      example: %{name: "web-server"}
    })
  end
end
