# edge_admin/lib/edge_admin_mcp/tools/nodes/create_public_enrollment_key.ex
defmodule EdgeAdminMcp.Tools.Nodes.CreatePublicEnrollmentKey do
  @moduledoc """
  Create an enrollment key for the configured default cluster without MCP
  authentication.

  This tool is available only when `PUBLIC_ENROLLMENT_KEY_ENABLED=true` and
  `DEFAULT_CLUSTER_NAME` points to an active cluster. The returned key is
  intended for agent enrollment and should be treated as a credential.
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Nodes
  alias EdgeAdmin.Nodes.Policies.EnrollmentKeyPolicies
  alias EdgeAdmin.Nodes.Views.EnrollmentKeyView

  @impl true
  def title, do: "Create Public Enrollment Key"

  @impl true
  def annotations, do: %{"destructiveHint" => false, "idempotentHint" => false, "openWorldHint" => false}

  schema do
  end

  @impl true
  def execute(_params, frame) do
    with :ok <- EnrollmentKeyPolicies.authorize(:create_for_public),
         {:ok, cluster} <- Nodes.get_cluster(Nodes.default_cluster_name()),
         {:ok, key} <- Nodes.create_enrollment_key(cluster, %{}) do
      {:reply, Response.json(Response.tool(), EnrollmentKeyView.render(key)), frame}
    else
      {:error, :forbidden} ->
        {:reply, error_response(:forbidden, "Public enrollment keys are disabled"), frame}

      {:error, :not_found} ->
        {:reply, error_response(:not_found, "Default cluster not found"), frame}

      {:error, reason} ->
        {:reply, error_response(reason), frame}
    end
  end
end
