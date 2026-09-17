# edge_admin/lib/edge_admin/nodes/validators/node_validators.ex
defmodule EdgeAdmin.Nodes.Validators.NodeValidators do
  @moduledoc """
  Pure value-level validators for node data.

  Forms and schemas adapt these predicates to their own Ecto changeset
  contracts. This module does not perform database queries or construct API
  errors.
  """

  @doc "Returns whether a value is a valid TCP/UDP port number."
  @spec valid_port?(term()) :: boolean()
  def valid_port?(port) when is_integer(port), do: port in 1..65_535
  def valid_port?(_port), do: false

  @doc "Returns whether a node network name has the expected cluster prefix."
  @spec valid_network_name?(term()) :: boolean()
  def valid_network_name?(name) when is_binary(name), do: String.starts_with?(name, "cluster-")
  def valid_network_name?(_name), do: false
end
