# edge_admin/lib/edge_admin/nodes/policies/enrollment_key_policy.ex
defmodule EdgeAdmin.Nodes.Policies.EnrollmentKeyPolicy do
  @moduledoc """
  Authorization policy for enrollment key actions.

  Reads application config directly so controllers stay clean.

  ## Usage

      with :ok <- EnrollmentKeyPolicy.authorize(:create_for_default) do
        ...
      end

      with :ok <- EnrollmentKeyPolicy.authorize(:create_for_public) do
        ...
      end
  """
  use EdgeAdmin.Policy

  @impl EdgeAdmin.Policy
  def authorize?(:create_for_default) do
    is_binary(Application.get_env(:edge_admin, :default_cluster_name))
  end

  def authorize?(:create_for_public) do
    Application.get_env(:edge_admin, :public_enrollment_key_enabled, false) == true and
      is_binary(Application.get_env(:edge_admin, :default_cluster_name))
  end

  def authorize?(_), do: false

  @doc """
  Returns the configured default cluster name.
  Call this after a successful `authorize/1` to get the resolved value
  without reading config twice.
  """
  @spec default_cluster_name() :: String.t() | nil
  def default_cluster_name, do: Application.get_env(:edge_admin, :default_cluster_name)
end
