# edge_admin/lib/edge_admin_mcp/tools/commands/list_commands.ex
defmodule EdgeAdminMcp.Tools.Commands.ListCommands do
  @moduledoc """
  List commands with filtering, sorting, and pagination.

  ## Filtering
  - `command_text` — exact match or wildcard (`ls*`, `*docker*`, `*restart`)
  - `has_timeout` — true: commands with a timeout set; false: commands without
  - `timeout_gte` / `timeout_lte` — timeout range in milliseconds
  - `has_expired_at` — true: commands with an expiration; false: commands without
  - `expired_at_gte` / `expired_at_lte` — expiration datetime range (ISO8601)
  - `inserted_at_gte` / `inserted_at_lte` — creation datetime range (ISO8601)
  - `updated_at_gte` / `updated_at_lte` — last-updated datetime range (ISO8601)

  ## Sorting
  - `order_by` — comma-separated fields: `timeout`, `expired_at`, `inserted_at`, `updated_at`
  - `order_directions` — comma-separated directions: `asc`, `desc` (one per order_by field)
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Commands
  alias EdgeAdminMcp.Tools.Commands.CommandData

  schema do
    field :page, :integer, default: 1, min: 1
    field :page_size, :integer, default: 20, min: 1
    field :command_text, :string, min_length: 1
    field :has_timeout, :boolean
    field :timeout_gte, :integer, min: 1
    field :timeout_lte, :integer, min: 1
    field :has_expired_at, :boolean
    field :expired_at_gte, :string
    field :expired_at_lte, :string
    field :inserted_at_gte, :string
    field :inserted_at_lte, :string
    field :updated_at_gte, :string
    field :updated_at_lte, :string
    field :order_by, :string
    field :order_directions, :string
  end

  @impl true
  def execute(params, frame) do
    case Commands.list_commands(build_query(params)) do
      {:ok, {commands, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(commands, meta, &CommandData.data/1)), frame}

      {:error, reason} ->
        {:reply, Response.error(Response.tool(), "Failed to list commands: #{inspect(reason)}"), frame}
    end
  end

  defp build_query(params) do
    %{"page" => params[:page] || 1, "page_size" => params[:page_size] || 20}
    |> put_if("command_text", params[:command_text])
    |> put_if("has_timeout", params[:has_timeout])
    |> put_if("timeout__gte", params[:timeout_gte])
    |> put_if("timeout__lte", params[:timeout_lte])
    |> put_if("has_expired_at", params[:has_expired_at])
    |> put_if("expired_at__gte", params[:expired_at_gte])
    |> put_if("expired_at__lte", params[:expired_at_lte])
    |> put_if("inserted_at__gte", params[:inserted_at_gte])
    |> put_if("inserted_at__lte", params[:inserted_at_lte])
    |> put_if("updated_at__gte", params[:updated_at_gte])
    |> put_if("updated_at__lte", params[:updated_at_lte])
    |> put_if("order_by", params[:order_by])
    |> put_if("order_directions", params[:order_directions])
  end

  defp paginated(items, meta, mapper) do
    %{
      data: Enum.map(items, mapper),
      pagination: %{
        page: meta.current_page,
        page_size: meta.page_size,
        total: meta.total_count,
        total_pages: meta.total_pages,
        has_next: meta.has_next_page?,
        has_prev: meta.has_previous_page?
      }
    }
  end

  defp put_if(m, _k, nil), do: m
  defp put_if(m, k, v), do: Map.put(m, k, v)
end
