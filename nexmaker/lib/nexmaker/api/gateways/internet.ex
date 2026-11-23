# nexmaker/lib/nexmaker/api/gateways/internet.ex
defmodule Nexmaker.Api.Gateways.Internet do
  @moduledoc """
  Internet egress resource operations for Netmaker.

  Exit-node selection for client nodes is handled separately by
  `Nexmaker.Api.Nodes.select_exit_node/4`.
  """

  alias Nexmaker.Api.Gateways.Egress

  @doc "Creates an Internet egress resource routed through the given node."
  @spec create(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def create(network_name, node_id, opts \\ []) do
    body = %{
      network: network_name,
      name: "#{node_id}-internet",
      type: "internet",
      nat: true,
      nodes: %{node_id => 256}
    }

    Egress.create_v1(body, opts)
  end

  @doc "Deletes an Internet egress resource by ID."
  @spec delete(String.t(), String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete(network_name, egress_id, opts \\ []) do
    Egress.delete_v1(egress_id, network_name, opts)
  end
end
