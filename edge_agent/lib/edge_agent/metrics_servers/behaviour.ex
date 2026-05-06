# edge_agent/lib/edge_agent/metrics_servers/behaviour.ex
defmodule EdgeAgent.MetricsServers.Behaviour do
  @moduledoc """
  Behaviour for metrics server operations to enable testing and abstraction.

  The "pid" returned by `start_servers/0` is an OS-level integer PID found via
  `pgrep` (see `EdgeAgent.MetricsServers.ProcessSupervisor.find_node_exporter_process/1`),
  not an Erlang `pid()`. The `start_result` type reflects that.
  """

  @type start_result :: {:ok, integer()} | {:error, term()}
  @type stop_result :: :ok | {:error, term()}
  @type status :: :running | :stopped | :error | :not_started | :unknown
  @type config :: map()
  @type ip_result :: {:ok, String.t()} | {:error, term()}

  @doc """
  Start the node_exporter and wireguard_exporter child processes. Idempotent —
  returns `{:ok, pid}` immediately if servers are already running.
  """
  @callback start_servers() :: start_result()

  @doc """
  Stop both exporter child processes. Idempotent — returns `:ok` when nothing
  is running.
  """
  @callback stop_servers() :: stop_result()

  @doc """
  Returns the live status of the exporter pair. `:not_started` / `:unknown`
  indicate the GenServer itself is missing or unresponsive (not the exporter
  binaries).
  """
  @callback servers_status() :: status()

  @doc """
  Returns a snapshot of the exporter configuration plus current `:status`,
  `:pid`, and `:primary_interface_ip`.
  """
  @callback servers_config() :: config()

  @doc """
  Detects (and caches) the host's primary outbound IPv4 address by shelling
  out to `ip route` / `ip addr`.
  """
  @callback get_primary_interface_ip() :: ip_result()
end
