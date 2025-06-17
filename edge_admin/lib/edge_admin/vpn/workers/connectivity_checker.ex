# edge_admin/lib/edge_admin/vpn/workers/connectivity_checker.ex
defmodule EdgeAdmin.VPN.Workers.ConnectivityChecker do
  @moduledoc """
  Oban worker that monitors VPN connectivity when the connection status is :connected.
  """

  use Oban.Worker, queue: :vpn, max_attempts: 3

  alias EdgeAdmin.VPN

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case VPN.check_and_update_connectivity() do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("VPN connectivity check failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
