# edge_agent/lib/edge_agent/local_scheduler/tasks.ex
defmodule EdgeAgent.LocalScheduler.Tasks do
  @moduledoc """
  Entry points called by `EdgeAgent.LocalScheduler`.

  Each function below is what a cron tick invokes directly — no Oban job, no
  DB write for scheduling state. Functions are responsible for their own
  runtime guards (e.g. "only run when VPN is down and fallback URLs are
  configured"). The underlying work modules (`Commands`, `Metrics`,
  `HealthCheck`, etc.) stay unaware of scheduling concerns so they can also
  be called directly from `Bootstrap`, controllers, and tests.

  All functions return `:ok`. Errors are logged inside the work; Quantum's
  telemetry events surface exceptions if they escape.
  """

  alias EdgeAgent.Commands
  alias EdgeAgent.EdgeClusters.Discovery
  alias EdgeAgent.EdgeClusters.HealthCheck
  alias EdgeAgent.Metrics
  alias EdgeAgent.SelfUpdates
  alias EdgeAgent.Settings
  alias EdgeAgent.Vpn

  require Logger

  @doc """
  Probe the VPN for `admin-*` peers and refresh the cached admin URL list.

  Always runs. Discovery returns an empty list if no admins are reachable;
  no separate guard is needed.
  """
  @spec discover_admins() :: :ok
  def discover_admins do
    Logger.debug("LocalScheduler: discover_admins started")
    {:ok, _network_name, admin_urls} = Discovery.discover_admins()
    Logger.debug("LocalScheduler: discover_admins done — #{length(admin_urls)} admin(s)")

    :telemetry.execute(
      [:edge_agent, :discovery, :scan],
      %{admins_found: length(admin_urls), count: 1, total: 1},
      %{status: if(admin_urls == [], do: :empty, else: :success)}
    )

    :ok
  end

  @doc """
  Report node health to admin via HTTP fallback.

  Skipped when VPN is up — admin pings the agent directly in that case.
  """
  @spec report_health_check() :: :ok
  def report_health_check do
    if http_fallback_mode?() do
      Logger.debug("LocalScheduler: report_health_check started")
      HealthCheck.report()
      Logger.debug("LocalScheduler: report_health_check done")
    else
      Logger.debug("LocalScheduler: report_health_check skipped (VPN up or fallback not configured)")
    end

    :ok
  end

  @doc """
  Push scraped local metrics to admin via HTTP fallback.

  Skipped when VPN is up — Prometheus scrapes directly through admin's
  cluster gateway in that case.
  """
  @spec push_metrics() :: :ok
  def push_metrics do
    if http_fallback_mode?() do
      Logger.debug("LocalScheduler: push_metrics started")
      Metrics.push_metrics()
      Logger.debug("LocalScheduler: push_metrics done")
    else
      Logger.debug("LocalScheduler: push_metrics skipped (VPN up or fallback not configured)")
    end

    :ok
  end

  @doc """
  Pull executions admin has for this node via HTTP fallback.

  Skipped when VPN is up — admin pushes executions to the agent directly.
  """
  @spec sync_unprocessed_executions() :: :ok
  def sync_unprocessed_executions do
    if http_fallback_mode?() do
      Logger.debug("LocalScheduler: sync_unprocessed_executions started")
      Commands.sync_unprocessed_command_executions()
      Logger.debug("LocalScheduler: sync_unprocessed_executions done")
    else
      Logger.debug("LocalScheduler: sync_unprocessed_executions skipped (VPN up or fallback not configured)")
    end

    :ok
  end

  @doc """
  Poll admin for a pending self-update request via HTTP fallback.

  Skipped when VPN is up, when no fallback is configured, or when self-update
  is disabled by env var.
  """
  @spec check_self_update() :: :ok
  def check_self_update do
    if http_fallback_mode?() and self_update_enabled?() do
      Logger.debug("LocalScheduler: check_self_update started")
      SelfUpdates.check_self_update()
      Logger.debug("LocalScheduler: check_self_update done")
    else
      Logger.debug("LocalScheduler: check_self_update skipped (VPN up, no fallback, or self-update disabled)")
    end

    :ok
  end

  @doc """
  Periodic `netclient pull` — daily DNS-recovery backstop.

  Disabled via `PULL_VPN_CONFIG_ENABLED=false` on resource-starved boxes
  where the pull causes disruptive interface resets.
  """
  @spec pull_vpn_config() :: :ok
  def pull_vpn_config do
    if Application.get_env(:edge_agent, :pull_vpn_config_enabled, true) do
      Logger.debug("LocalScheduler: pull_vpn_config started")

      result =
        case Vpn.pull() do
          :ok ->
            Logger.debug("LocalScheduler: pull_vpn_config done")
            :success

          {:error, reason} ->
            Logger.warning("LocalScheduler: pull_vpn_config failed: #{inspect(reason)}")
            :failure
        end

      :telemetry.execute([:edge_agent, :vpn, :pull], %{count: 1}, %{result: result})
    else
      Logger.debug("LocalScheduler: pull_vpn_config skipped (PULL_VPN_CONFIG_ENABLED=false)")
    end

    :ok
  end

  # -----------------------------------------------------------------------
  # Guards
  # -----------------------------------------------------------------------

  defp http_fallback_mode? do
    Settings.get_admin_urls() == [] and Settings.get_admin_fallback_urls() != []
  end

  defp self_update_enabled? do
    Application.get_env(:edge_agent, :self_update_enabled, false)
  end
end
