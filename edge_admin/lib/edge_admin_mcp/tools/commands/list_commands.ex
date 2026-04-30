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
  alias EdgeAdminMcp.FlopParams
  alias EdgeAdminMcp.Tools.Commands.CommandData

  @impl true
  def title, do: "List Commands"
  @impl true
  def annotations, do: %{"readOnlyHint" => true}

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
    query =
      FlopParams.build(params,
        passthrough: [:command_text, :has_timeout, :has_expired_at],
        ranges: [:timeout, :expired_at, :inserted_at, :updated_at]
      )

    case Commands.list_commands(query) do
      {:ok, {commands, meta}} ->
        {:reply, Response.json(Response.tool(), paginated(commands, meta, &CommandData.data/1)), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
