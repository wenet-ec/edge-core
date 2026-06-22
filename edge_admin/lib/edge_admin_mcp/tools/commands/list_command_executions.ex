# edge_admin/lib/edge_admin_mcp/tools/commands/list_command_executions.ex
defmodule EdgeAdminMcp.Tools.Commands.ListCommandExecutions do
  @moduledoc """
  List command executions with filtering, sorting, and pagination.

  ## Filtering
  - `command_id_in` — filter by command UUIDs (array of UUIDs)
  - `node_id_in` — filter by node UUIDs (array of UUIDs)
  - `status_in` — one or more of `pending`, `sent`, `completed`, `cancelled`, `expired`
  - `target_all` — true: executions targeting all nodes; false: targeted executions
  - `exit_code` — exact exit code
  - `exit_code_gte` / `exit_code_lte` — exit code range (e.g. `exit_code_gte: 1` for all failures)
  - `output` — text search in output (exact match or wildcard: `*error*`, `*failed`)
  - `has_output` — true: executions with output present; false: executions without output
  - `cluster_name` — filter by cluster name — exact match or wildcard (`prod*`, `*staging`)
  - `cluster_name_in` — IN match on cluster name (array)
  - `has_cluster` — true: cluster-wide executions; false: non-cluster-wide
  - `inserted_at_gte` / `inserted_at_lte` — creation datetime range (ISO8601)
  - `updated_at_gte` / `updated_at_lte` — last-updated datetime range (ISO8601)
  - `sent_at_gte` / `sent_at_lte` — sent datetime range (ISO8601)
  - `completed_at_gte` / `completed_at_lte` — completed datetime range (ISO8601)
  - `cancelled_at_gte` / `cancelled_at_lte` — cancelled datetime range (ISO8601)

  ## Sorting
  - `order_by` — comma-separated fields: `status`, `exit_code`, `sent_at`, `completed_at`, `cancelled_at`, `inserted_at`, `updated_at`
  - `order_directions` — comma-separated directions: `asc`, `desc` (one per order_by field)
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Commands
  alias EdgeAdmin.Commands.Schemas.CommandExecution
  alias EdgeAdmin.Commands.Views.CommandExecutionView
  alias EdgeAdminMcp.FlopParams

  @status_enum CommandExecution.status_strings()

  @impl true
  def title, do: "List Command Executions"
  @impl true
  def annotations, do: %{"readOnlyHint" => true, "openWorldHint" => false}

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :command_id_in, {:list, :string}
    field :node_id_in, {:list, :string}
    field :status_in, {:list, {:enum, @status_enum}}
    field :target_all, :boolean
    field :exit_code, :integer
    field :exit_code_gte, :integer
    field :exit_code_lte, :integer
    field :output, :string, min_length: 1
    field :has_output, :boolean
    field :cluster_name_in, {:list, :string}
    field :has_cluster, :boolean
    field :inserted_at_gte, :string
    field :inserted_at_lte, :string
    field :updated_at_gte, :string
    field :updated_at_lte, :string
    field :sent_at_gte, :string
    field :sent_at_lte, :string
    field :completed_at_gte, :string
    field :completed_at_lte, :string
    field :cancelled_at_gte, :string
    field :cancelled_at_lte, :string
    field :order_by, :string
    field :order_directions, :string
  end

  @impl true
  def execute(params, frame) do
    query =
      FlopParams.build(params,
        passthrough: [
          :exit_code,
          :output
        ],
        boolean_filters: [:target_all, :has_output, :has_cluster],
        multi: [:command_id, :node_id, :cluster_name, :status],
        ranges: [:exit_code, :inserted_at, :updated_at, :sent_at, :completed_at, :cancelled_at]
      )

    case Commands.list_command_executions(query) do
      {:ok, {executions, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(executions, meta, &CommandExecutionView.render/1)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
