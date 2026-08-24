# edge_admin/lib/edge_admin/commands/policies/command_execution_policies.ex
defmodule EdgeAdmin.Commands.Policies.CommandExecutionPolicies do
  @moduledoc """
  Authorization policy for command execution actions.

  ## Usage

      with :ok <- CommandExecutionPolicies.authorize({:update, node, execution}) do
        ...
      end
  """
  use EdgeAdmin.Policy

  @impl EdgeAdmin.Policy
  def authorize?({:update, %{id: node_id}, %{node_id: node_id}}), do: true
  def authorize?(_), do: false
end
