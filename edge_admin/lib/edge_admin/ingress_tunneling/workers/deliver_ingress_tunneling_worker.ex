# edge_admin/lib/edge_admin/ingress_tunneling/workers/deliver_ingress_tunneling_worker.ex
defmodule EdgeAdmin.IngressTunneling.Workers.DeliverIngressTunnelingWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :ingress_tunneling,
    max_attempts: 3,
    unique: [period: 300, states: :incomplete, keys: [:node_id]]

  alias EdgeAdmin.IngressTunneling

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"node_id" => node_id}}) do
    IngressTunneling.deliver_ingress_tunneling(node_id)
  end
end
