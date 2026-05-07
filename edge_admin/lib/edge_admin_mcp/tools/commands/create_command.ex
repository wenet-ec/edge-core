# edge_admin/lib/edge_admin_mcp/tools/commands/create_command.ex
defmodule EdgeAdminMcp.Tools.Commands.CreateCommand do
  @moduledoc """
  Create a command to run on one or more edge nodes.

  ## command_text

  The shell string to execute. Multi-line scripts are supported — newlines
  are preserved and the agent runs the whole block in a single shell. Set
  variables, chain commands, or invoke `systemctl` etc.:

      ABC=value
      echo $ABC
      systemctl restart nginx

  ## timeout

  Optional. Milliseconds. Must be > 0. Omit (or pass null) for no timeout.

  ## expired_at

  Optional. ISO8601 datetime, must be in the future. After this time, any
  executions still `pending` or `sent` are automatically marked `expired`.
  Immutable after creation.

  ## targeting

  Required map. Three forms:

  - `%{"type" => "all"}` — every healthy node in the fleet.
  - `%{"type" => "nodes", "node_ids" => ["<uuid>", ...]}` — specific nodes by ID. IDs are deduplicated.
  - `%{"type" => "clusters", "cluster_names" => ["prod", ...]}` — every node in those clusters. Names are deduplicated.

  Optional `node_filters` and `cluster_filters` further refine the target
  set (AND logic with the type/ids/names selection):

  - `node_filters` keys: `id_type` (`"persistent"` | `"random"`), `status`
    (`"healthy"` | `"unhealthy"` | `"unreachable"`), `cluster_name` (string,
    wildcards `prod*` / `*staging` / `*rod*`), `version` (string with
    wildcards), `self_update_enabled` (boolean), `last_seen_at__gte` /
    `last_seen_at__lte` / `inserted_at__gte` / `inserted_at__lte` /
    `updated_at__gte` / `updated_at__lte` (ISO8601 datetime or date).
  - `cluster_filters` keys: `name` (string with wildcards), `ipv4_range`
    (CIDR string), `node_count` / `node_count__gte` / `node_count__lte`
    (integer), `has_node_limit` (boolean), `inserted_at__gte` /
    `inserted_at__lte` / `updated_at__gte` / `updated_at__lte`.

  Example with filters:

      %{
        "type" => "clusters",
        "cluster_names" => ["prod", "staging"],
        "node_filters" => %{"status" => "healthy", "id_type" => "persistent"}
      }

  ## Result

  Returns the created command (one row), not the executions. Each targeted
  node gets one `command_execution` created in the background — list them
  via `list_command_executions` filtered by `command_id` to track delivery.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Commands
  alias EdgeAdminMcp.Tools.Commands.CommandData

  @impl true
  def title, do: "Create Command"
  @impl true
  def annotations, do: %{"destructiveHint" => false, "idempotentHint" => false, "openWorldHint" => false}

  schema do
    field :command_text, {:required, :string}, min_length: 1
    field :targeting, {:required, :map}
    field :timeout, :integer, min: 1
    field :expired_at, :string
  end

  @impl true
  def execute(params, frame) do
    attrs =
      %{"command_text" => params.command_text, "targeting" => params.targeting}
      |> put_if("timeout", params[:timeout])
      |> put_if("expired_at", params[:expired_at])

    case Commands.create_command_and_executions(attrs) do
      {:ok, command} ->
        {:reply, Response.json(Response.tool(), CommandData.data(command)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
