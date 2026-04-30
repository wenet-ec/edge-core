# edge_admin/lib/edge_admin_web/schemas/path_params.ex
defmodule EdgeAdminWeb.Schemas.PathParams do
  @moduledoc """
  Reusable OpenAPI path parameter specs.

  Most resources are addressed either by a UUID (nodes, commands, executions,
  enrollment keys, etc.) or by a name with a small DNS-style charset (clusters,
  ssh usernames). Centralising the schemas keeps validation consistent across
  the codebase and makes future format changes a single edit.

  ## Usage

      operation(:show,
        parameters: [
          PathParams.uuid(:id, "Node ID"),
          PathParams.cluster_name(:name, "Cluster name")
        ],
        ...
      )
  """

  alias OpenApiSpex.Schema

  # Cluster name pattern — also enforced server-side in EdgeAdmin.Nodes.
  # Lowercase alphanumeric with hyphens, no leading/trailing hyphen, max 24 chars.
  @cluster_name_pattern "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"
  @cluster_name_max_length 24

  @doc "UUID path parameter (e.g. `:id`, `:node_id`, `:command_id`)."
  @spec uuid(atom(), String.t()) :: {atom(), keyword()}
  def uuid(name, description) when is_atom(name) and is_binary(description) do
    {name,
     [
       in: :path,
       description: description,
       schema: %Schema{type: :string, format: :uuid}
     ]}
  end

  @doc """
  Cluster-name path parameter — DNS-style charset, max 24 chars.

  Used for cluster, network, and similar names that travel through the
  Netmaker/WireGuard stack.
  """
  @spec cluster_name(atom(), String.t()) :: {atom(), keyword()}
  def cluster_name(name, description) when is_atom(name) and is_binary(description) do
    {name,
     [
       in: :path,
       description: description,
       schema: %Schema{
         type: :string,
         pattern: @cluster_name_pattern,
         maxLength: @cluster_name_max_length
       }
     ]}
  end
end
