# edge_admin/lib/edge_admin_mcp/tools/commands/list_command_executions.ex
defmodule EdgeAdminMcp.Tools.Commands.ListCommandExecutions do
  @moduledoc """
  List command executions with filtering, sorting, and pagination.

  ## Filtering
  - `command_id` — filter by command UUID
  - `node_id` — filter by node UUID
  - `status` — `pending`, `sent`, `completed`, `cancelled`, `expired`
  - `target_all` — true: executions targeting all nodes; false: targeted executions
  - `exit_code` — exact exit code
  - `exit_code_gte` / `exit_code_lte` — exit code range (e.g. `exit_code_gte: 1` for all failures)
  - `output` — text search in output (exact match or wildcard: `*error*`, `*failed`)
  - `has_output` — true: executions with output present; false: executions without output
  - `cluster_name` — filter by cluster name (exact match or wildcard: `prod*`, `*staging`)
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
  alias EdgeAdminMcp.Tools.Commands.CommandExecutionData

  @impl true
  def title, do: "List Command Executions"
  @impl true
  def annotations, do: %{"readOnlyHint" => true}

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :command_id, :string
    field :node_id, :string
    field :status, {:enum, ["pending", "sent", "completed", "cancelled", "expired"]}
    field :target_all, :boolean
    field :exit_code, :integer
    field :exit_code_gte, :integer
    field :exit_code_lte, :integer
    field :output, :string, min_length: 1
    field :has_output, :boolean
    field :cluster_name, :string, min_length: 1
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
    case Commands.list_command_executions(build_query(params)) do
      {:ok, {executions, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(executions, meta, &CommandExecutionData.data/1)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end

  defp build_query(params) do
    %{"page" => params[:page] || 1, "page_size" => params[:page_size] || 20}
    |> put_if("command_id", params[:command_id])
    |> put_if("node_id", params[:node_id])
    |> put_if("status", params[:status])
    |> put_if("target_all", params[:target_all])
    |> put_if("exit_code", params[:exit_code])
    |> put_if("exit_code__gte", params[:exit_code_gte])
    |> put_if("exit_code__lte", params[:exit_code_lte])
    |> put_if("output", params[:output])
    |> put_if("has_output", params[:has_output])
    |> put_if("cluster_name", params[:cluster_name])
    |> put_if("has_cluster", params[:has_cluster])
    |> put_if("inserted_at__gte", params[:inserted_at_gte])
    |> put_if("inserted_at__lte", params[:inserted_at_lte])
    |> put_if("updated_at__gte", params[:updated_at_gte])
    |> put_if("updated_at__lte", params[:updated_at_lte])
    |> put_if("sent_at__gte", params[:sent_at_gte])
    |> put_if("sent_at__lte", params[:sent_at_lte])
    |> put_if("completed_at__gte", params[:completed_at_gte])
    |> put_if("completed_at__lte", params[:completed_at_lte])
    |> put_if("cancelled_at__gte", params[:cancelled_at_gte])
    |> put_if("cancelled_at__lte", params[:cancelled_at_lte])
    |> put_if("order_by", params[:order_by])
    |> put_if("order_directions", params[:order_directions])
  end
end
