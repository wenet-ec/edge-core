# edge_admin/lib/edge_admin_mcp/tools/nodes/create_default_enrollment_key.ex
defmodule EdgeAdminMcp.Tools.Nodes.CreateDefaultEnrollmentKey do
  @moduledoc """
  Create an enrollment key for the configured default cluster.

  This is the authenticated MCP equivalent of the REST default-cluster
  convenience endpoint. The default cluster must be configured with
  `DEFAULT_CLUSTER_NAME` and must exist as an active cluster.

  - `name` — optional human-readable label for this key.
  - `uses_remaining` — optional positive integer. Omit for the default of
    1 (single-use). Pass a number for a finite-use key.
  - `expires_at` — optional ISO8601 datetime. Omit for no expiry.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Policies.EnrollmentKeyPolicies
  alias EdgeAdmin.Nodes.Views.EnrollmentKeyView

  @impl true
  def title, do: "Create Default Enrollment Key"

  @impl true
  def annotations, do: %{"destructiveHint" => false, "idempotentHint" => false, "openWorldHint" => false}

  schema do
    field :name, :string
    field :uses_remaining, :integer, min: 1
    field :expires_at, :string
  end

  @impl true
  def execute(params, frame) do
    with :ok <- EnrollmentKeyPolicies.authorize(:create_for_default),
         {:ok, cluster} <- Nodes.get_cluster(Nodes.default_cluster_name()) do
      attrs =
        %{}
        |> put_if("name", params[:name])
        |> put_if("uses_remaining", params[:uses_remaining])
        |> put_if("expires_at", params[:expires_at])

      case Nodes.create_enrollment_key(cluster, attrs) do
        {:ok, key} ->
          {:reply, Response.json(Response.tool(), EnrollmentKeyView.render(key)), frame}

        {:error, reason} ->
          {:reply, error_response(reason), frame}
      end
    else
      {:error, :forbidden} ->
        {:reply, error_response(:forbidden, "Default cluster is not configured"), frame}

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Default cluster not found"), frame}
    end
  end
end
