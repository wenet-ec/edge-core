# edge_admin/lib/edge_admin/commands/policies/command_execution_policy.ex
defmodule EdgeAdmin.Commands.Policies.CommandExecutionPolicy do
  @moduledoc """
  Authorization policy for command execution actions.

  ## Usage

      with :ok <- CommandExecutionPolicy.authorize({:update, node, execution}) do
        ...
      end
  """
  use EdgeAdmin.Policy

  @impl EdgeAdmin.Policy
  def authorize?({:update, %{id: node_id}, %{node_id: node_id}}), do: true
  def authorize?(_), do: false
end
