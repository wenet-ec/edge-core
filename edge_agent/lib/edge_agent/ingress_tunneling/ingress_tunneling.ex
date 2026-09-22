# edge_agent/lib/edge_agent/ingress_tunneling/ingress_tunneling.ex
defmodule EdgeAgent.IngressTunneling do
  @moduledoc false

  alias EdgeAgent.IngressTunneling.Identity
  alias EdgeAgent.Settings

  @spec upsert_ingress_tunneling(map()) :: {:ok, map()} | {:error, term()}
  def upsert_ingress_tunneling(desired_state) when is_map(desired_state) do
    with :ok <- Identity.verify_public_key(Map.get(desired_state, "ingress_public_key")),
         {:ok, _setting} <- Settings.set_ingress_tunneling(desired_state) do
      {:ok, desired_state}
    end
  end
end
