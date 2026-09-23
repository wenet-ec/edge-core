# edge_agent/lib/edge_agent/ingress_tunneling/ingress_tunneling.ex
defmodule EdgeAgent.IngressTunneling do
  @moduledoc """
  Stores the Admin-provided Ingress Tunneling desired state.

  Updates are accepted only when the requested Ingress public key matches the
  public key derived from this Agent's durable private identity. The private
  key remains in Agent settings and is never part of the desired-state map.
  """

  alias EdgeAgent.IngressTunneling.Identity
  alias EdgeAgent.Settings

  @doc "Validates and replaces the persisted Ingress Tunneling desired state."
  @spec upsert_ingress_tunneling(map()) :: {:ok, map()} | {:error, term()}
  def upsert_ingress_tunneling(desired_state) when is_map(desired_state) do
    with :ok <- Identity.verify_public_key(Map.get(desired_state, "ingress_public_key")),
         {:ok, _setting} <- Settings.set_ingress_tunneling(desired_state) do
      {:ok, desired_state}
    end
  end
end
