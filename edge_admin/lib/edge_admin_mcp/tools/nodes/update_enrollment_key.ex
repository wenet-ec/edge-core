# edge_admin/lib/edge_admin_mcp/tools/nodes/update_enrollment_key.ex
defmodule EdgeAdminMcp.Tools.Nodes.UpdateEnrollmentKey do
  @moduledoc """
  Update an enrollment key's `name`, `uses_remaining`, or `expired_at`.

  Three ways each field can be passed:

  - **Omit the field** — leave it unchanged.
  - **Pass a value** — set the field to that value.
  - **Pass `null`** — clear the field. `name: null` removes the label.
    `uses_remaining: null` makes the key unlimited. `expired_at: null`
    removes the expiry.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Schemas.EnrollmentKey

  @impl true
  def title, do: "Update Enrollment Key"
  @impl true
  def annotations, do: %{"destructiveHint" => false, "idempotentHint" => true, "openWorldHint" => false}

  schema do
    field :enrollment_key_id, {:required, :string}
    field :name, :string
    field :uses_remaining, :integer, min: 1
    field :expired_at, :string
  end

  @impl true
  def execute(params, frame) do
    case Nodes.get_enrollment_key(params.enrollment_key_id) do
      {:ok, key} ->
        attrs =
          %{}
          |> put_if_present("name", params, :name)
          |> put_if_present("uses_remaining", params, :uses_remaining)
          |> put_if_present("expired_at", params, :expired_at)

        case Nodes.update_enrollment_key(key, attrs) do
          {:ok, updated} ->
            {:reply, Response.json(Response.tool(), EnrollmentKey.to_public(updated)), frame}

          {:error, reason} ->
            {:reply, error_response(reason), frame}
        end

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Enrollment key #{params.enrollment_key_id} not found"), frame}
    end
  end
end
