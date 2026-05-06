# edge_admin/lib/edge_admin_mcp/tools/metrics/get_admin_metrics.ex
defmodule EdgeAdminMcp.Tools.Metrics.GetAdminMetrics do
  @moduledoc """
  Get metrics for this admin instance from edge_admin PromEx.

  Returns 16 sections covering the admin's full operational surface:

  - `application` — BEAM/VM stats (memory, processes, schedulers)
  - `metadata` — cluster metadata recompute counters
  - `membership` — admin Erlang/`:syn` membership health
  - `discovery` — admin peer discovery via VPN
  - `nodes` — node count + per-cluster health distribution
  - `quantum` — LocalScheduler job runs
  - `vpn` — Netmaker API calls + netclient pulls
  - `commands` — command pipeline (creation, dispatch, completion)
  - `ssh` — SSH credential verification calls from agents
  - `reconciliation` — cluster reconciliation Oban runs
  - `self_updates` — self-update request processing
  - `gateways` — per-cluster Gateway proxy health
  - `proxy` — admin's HTTP/SOCKS5 forward proxy
  - `event_broker` — broker publish (NATS/Kafka/etc.) outcomes
  - `webhook` — webhook delivery outcomes
  - `oban_queues` — per-queue depth and execution stats
  """
  use EdgeAdminMcp, :tool

  alias EdgeAdmin.Metrics

  @impl true
  def title, do: "Get Admin Metrics"
  @impl true
  def annotations, do: %{"readOnlyHint" => true}

  schema do
  end

  @impl true
  def execute(_params, frame) do
    case Metrics.get_admin_metrics() do
      {:ok, metrics} ->
        {:reply, Response.json(Response.tool(), metrics), frame}

      {:error, _reason} ->
        {:reply, error_response(:service_unavailable), frame}
    end
  end
end
