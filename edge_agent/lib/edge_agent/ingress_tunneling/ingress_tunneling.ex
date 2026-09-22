# edge_agent/lib/edge_agent/ingress_tunneling/ingress_tunneling.ex
defmodule EdgeAgent.IngressTunneling do
  @moduledoc false
  alias EdgeAgent.Settings

  @spec upsert_ingress_tunneling(map()) :: {:ok, map()} | {:error, term()}
  def upsert_ingress_tunneling(desired_state) when is_map(desired_state) do
    case Settings.set_ingress_tunneling(desired_state) do
      {:ok, _setting} -> {:ok, desired_state}
      error -> error
    end
  end
end
