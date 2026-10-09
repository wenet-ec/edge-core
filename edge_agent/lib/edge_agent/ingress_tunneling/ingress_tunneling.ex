# edge_agent/lib/edge_agent/ingress_tunneling/ingress_tunneling.ex
defmodule EdgeAgent.IngressTunneling do
  @moduledoc """
  Stores the Admin-provided Ingress Tunneling configuration.

  Updates are accepted only when the configuration's Ingress public key matches the
  public key derived from this Agent's durable private identity. The private
  key remains in Agent settings and is never part of the configuration map.
  """

  alias EdgeAgent.IngressTunneling.Configuration
  alias EdgeAgent.IngressTunneling.Identity
  alias EdgeAgent.IngressTunneling.Reconciler
  alias EdgeAgent.Settings

  @doc "Validates and replaces the persisted Ingress Tunneling configuration."
  @spec upsert_ingress_tunneling(map()) :: {:ok, map()} | {:error, term()}
  def upsert_ingress_tunneling(ingress_tunneling) when is_map(ingress_tunneling) do
    with {:ok, ingress_tunneling} <- Configuration.validate(ingress_tunneling),
         :ok <- Identity.verify_public_key(Map.get(ingress_tunneling, "ingress_public_key")),
         {:ok, _setting} <- Settings.set_ingress_tunneling(ingress_tunneling) do
      if Process.whereis(Reconciler), do: Reconciler.reconcile()
      {:ok, ingress_tunneling}
    end
  end
end
