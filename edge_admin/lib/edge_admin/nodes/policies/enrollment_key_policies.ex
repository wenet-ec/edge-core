# edge_admin/lib/edge_admin/nodes/policies/enrollment_key_policies.ex
defmodule EdgeAdmin.Nodes.Policies.EnrollmentKeyPolicies do
  @moduledoc """
  Authorization policy for enrollment key actions.

  Reads application config directly so controllers stay clean.

  ## Usage

      with :ok <- EnrollmentKeyPolicies.authorize(:create_for_default) do
        ...
      end

      with :ok <- EnrollmentKeyPolicies.authorize(:create_for_public) do
        ...
      end
  """
  use EdgeAdmin.Policy

  @impl EdgeAdmin.Policy
  @doc "Authorizes an enrollment-key action from the configured policy."
  @spec authorize?(atom()) :: boolean()
  def authorize?(:create_for_default) do
    is_binary(Application.get_env(:edge_admin, :default_cluster_name))
  end

  def authorize?(:create_for_public) do
    Application.get_env(:edge_admin, :public_enrollment_key_enabled, false) == true and
      is_binary(Application.get_env(:edge_admin, :default_cluster_name))
  end

  def authorize?(_), do: false
end
