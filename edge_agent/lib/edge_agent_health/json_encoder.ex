# edge_agent/lib/edge_agent_health/json_encoder.ex
defmodule EdgeAgentHealth.JsonEncoder do
  @moduledoc false

  @spec encode!(term(), keyword()) :: String.t()
  def encode!(value, _opts), do: JSON.encode!(value)
end
