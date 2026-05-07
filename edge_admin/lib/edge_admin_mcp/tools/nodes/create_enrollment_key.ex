# edge_admin/lib/edge_admin_mcp/tools/nodes/create_enrollment_key.ex
defmodule EdgeAdminMcp.Tools.Nodes.CreateEnrollmentKey do
  @moduledoc """
  Create an enrollment key for a cluster. Agents use this key to join the
  VPN mesh.

  - `cluster_name` — required. The cluster the key enrolls agents into.
  - `name` — optional human-readable label for this key. Display only —
    not used for lookup or authentication.
  - `uses_remaining` — optional positive integer. Omit for the default of
    1 (single-use). Pass a number for a finite-use key.
  - `expired_at` — optional ISO8601 datetime. Omit for no expiry.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdminMcp.Tools.Nodes.EnrollmentKeyData

  @impl true
  def title, do: "Create Enrollment Key"
  @impl true
  def annotations, do: %{"destructiveHint" => false, "idempotentHint" => false, "openWorldHint" => false}

  schema do
    field :cluster_name, {:required, :string}, min_length: 1
    field :name, :string
    field :uses_remaining, :integer, min: 1
    field :expired_at, :string
  end

  @impl true
  def execute(params, frame) do
    case Nodes.get_cluster(params.cluster_name) do
      {:ok, cluster} ->
        attrs =
          %{}
          |> put_if("name", params[:name])
          |> put_if("uses_remaining", params[:uses_remaining])
          |> put_if("expired_at", params[:expired_at])

        case Nodes.create_enrollment_key(cluster, attrs) do
          {:ok, key} ->
            {:reply, Response.json(Response.tool(), EnrollmentKeyData.data(key)), frame}

          {:error, reason} ->
            {:reply, error_response(reason), frame}
        end

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Cluster #{params.cluster_name} not found"), frame}
    end
  end
end
