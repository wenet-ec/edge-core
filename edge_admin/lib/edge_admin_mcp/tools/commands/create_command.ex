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

  Required nested object selecting which nodes the command runs on. Supports
  three top-level shapes (`type: "all" | "nodes" | "clusters"`) with optional
  `node_filters` / `cluster_filters` for refinement (AND logic). Full shape
  reference and field-level docs: `EdgeAdmin.Nodes.Targeting`.

  Quick examples:

      %{"type" => "all"}
      %{"type" => "nodes", "node_ids" => ["<uuid>", ...]}
      %{"type" => "clusters", "cluster_names" => ["prod", "staging"],
        "node_filters" => %{"status" => "healthy", "id_type" => "persistent"}}

  ## Result

  Returns the created command (one row), not the executions. Each targeted
  node gets one `command_execution` created in the background — list them
  via `list_command_executions` filtered by `command_id` to track delivery.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Commands
  alias EdgeAdmin.Commands.Views.CommandView
  alias EdgeAdmin.Nodes.Targeting

  @impl true
  def title, do: "Create Command"
  @impl true
  def annotations, do: %{"destructiveHint" => false, "idempotentHint" => false, "openWorldHint" => false}

  schema do
    field :command_text, {:required, :string}, min_length: 1
    field :targeting, {:required, Targeting.peri_schema()}
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
        {:reply, Response.json(Response.tool(), CommandView.render(command)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
