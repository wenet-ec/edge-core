# edge_admin/lib/edge_admin_health/json_encoder.ex
defmodule EdgeAdminHealth.JsonEncoder do
  @moduledoc false

  @spec encode!(term(), keyword()) :: String.t()
  def encode!(value, _opts), do: JSON.encode!(value)
end
