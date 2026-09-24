# edge_admin/lib/edge_admin/ingress_tunneling/persistence.ex
defmodule EdgeAdmin.IngressTunneling.Persistence do
  @moduledoc "Adapter-aware row locks used by Ingress Tunneling workflows."

  import Ecto.Query, warn: false

  alias Ecto.Adapters.Postgres
  alias EdgeAdmin.IngressTunneling.Schemas.TunnelClient
  alias EdgeAdmin.Repo

  @doc "Returns and locks a Tunnel Client by ID when the adapter supports row locks."
  @spec lock_tunnel_client(String.t()) :: TunnelClient.t() | nil
  def lock_tunnel_client(id) do
    query = from(client in TunnelClient, where: client.id == ^id)

    query =
      case Repo.__adapter__() do
        Postgres -> from(client in query, lock: "FOR UPDATE")
        _ -> query
      end

    Repo.one(query)
  end
end
