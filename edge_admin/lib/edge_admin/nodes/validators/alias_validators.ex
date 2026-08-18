# edge_admin/lib/edge_admin/nodes/validators/alias_validators.ex
defmodule EdgeAdmin.Nodes.Validators.AliasValidators do
  @moduledoc "Pure value-level validators for node aliases."

  alias EdgeAdmin.Naming

  @spec valid_name?(term()) :: boolean()
  def valid_name?(name) when is_binary(name) do
    byte_size(name) >= Naming.alias_name_min_length() and
      byte_size(name) <= Naming.alias_name_max_length() and
      Regex.match?(Naming.alias_name_regex(), name)
  end

  def valid_name?(_name), do: false
end
