# edge_agent/lib/edge_agent/diagnostics/diagnostics.ex
defmodule EdgeAgent.Diagnostics do
  @moduledoc """
  Edge Agent self-diagnostics.
  """

  alias EdgeAgent.AdminGateway.Client
  alias EdgeAgent.Diagnostics.WireguardInterface
  alias EdgeAgent.Settings
  alias EdgeAgent.Vpn
  alias EdgeAgent.Vpn.DerpMapCache

  @check_timeout 2_000

  @type status :: :pass | :warn | :fail

  @spec snapshot() :: map()
  def snapshot do
    build_report(local_checks())
  end

  @spec run() :: map()
  def run do
    build_report(local_checks())
  end

  @doc """
  Collects and pushes a local diagnostic snapshot while in HTTP fallback mode.
  """
  @spec push() :: :ok | {:error, term()}
  def push do
    result =
      snapshot()
      |> Client.push_diagnostics()
      |> case do
        {:ok, _response} -> :ok
        {:error, reason} -> {:error, reason}
      end

    :telemetry.execute(
      [:edge_agent, :diagnostics, :push],
      %{count: 1},
      %{result: if(match?(:ok, result), do: :success, else: :failure)}
    )

    result
  end

  defp local_checks do
    [
      {"wireguard_interface", &WireguardInterface.check/0},
      {"netclient", &edge_vpn_cli_check/0},
      {"networks", &networks_check/0},
      {"configured_peers", &configured_peers_check/0},
      {"derp_map", &derp_map_check/0},
      {"database", &EdgeAgentHealth.database_health/0},
      {"bootstrap", &EdgeAgentHealth.bootstrap_health/0},
      {"ssh_server", &EdgeAgentHealth.ssh_server_health/0},
      {"metrics_servers", &EdgeAgentHealth.metrics_servers_health/0},
      {"proxy_servers", &EdgeAgentHealth.proxy_servers_health/0}
    ]
  end

  defp build_report(checks) do
    checks
    |> Task.async_stream(
      fn {name, check} -> run_check(name, check) end,
      timeout: @check_timeout,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.zip(checks)
    |> Enum.map(fn
      {{:ok, result}, _check} -> result
      {{:exit, :timeout}, {name, _check}} -> failed_check(name, "Check timed out")
      {{:exit, reason}, {name, _check}} -> failed_check(name, "Check exited: #{inspect(reason)}")
    end)
    |> then(fn results ->
      %{
        "collected_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
        "overall" => overall_status(results),
        "checks" => results
      }
    end)
  end

  defp run_check(name, check) do
    started_at = System.monotonic_time(:millisecond)

    result =
      try do
        check.()
      rescue
        error -> {:error, "Check raised: #{Exception.message(error)}"}
      catch
        kind, reason -> {:error, "Check #{kind}: #{inspect(reason)}"}
      end

    duration_ms = System.monotonic_time(:millisecond) - started_at
    normalize_check_result(name, result, duration_ms)
  end

  defp normalize_check_result(name, :ok, duration_ms), do: passed_check(name, duration_ms)

  defp normalize_check_result(name, {:ok, :healthy, info}, duration_ms),
    do: passed_check(name, duration_ms, sanitize_info(info))

  defp normalize_check_result(name, {:ok, :degraded, info}, duration_ms),
    do: warned_check(name, duration_ms, "Edge VPN CLI is degraded", sanitize_info(info))

  defp normalize_check_result(name, {:ok, :unhealthy, info}, duration_ms),
    do: failed_check(name, "Edge VPN CLI is unhealthy: #{inspect(sanitize_info(info))}", duration_ms)

  defp normalize_check_result(name, {:ok, value}, duration_ms),
    do: passed_check(name, duration_ms, sanitize_info(value))

  defp normalize_check_result(name, {:warn, summary, details}, duration_ms),
    do: warned_check(name, duration_ms, summary, details)

  defp normalize_check_result(name, {:error, summary, details}, duration_ms),
    do: failed_check(name, summary, duration_ms, details)

  defp normalize_check_result(name, {:error, reason}, duration_ms), do: failed_check(name, inspect(reason), duration_ms)

  defp normalize_check_result(name, result, duration_ms),
    do: failed_check(name, "Unexpected result: #{inspect(result)}", duration_ms)

  defp edge_vpn_cli_check, do: Vpn.edge_vpn_cli_health_check()
  defp networks_check, do: Vpn.list_networks()

  defp configured_peers_check do
    case Vpn.list_peers() do
      {:ok, %{"peers" => peers}} when is_map(peers) ->
        peer_groups = Map.values(peers)

        peer_count =
          Enum.reduce(peer_groups, 0, fn
            peers, total when is_list(peers) -> total + length(peers)
            _peers, total -> total
          end)

        {:ok, %{networks: map_size(peers), peers: peer_count}}

      {:ok, peers} ->
        {:ok, %{peer_data: sanitize_info(peers)}}

      {:error, reason} ->
        {:warn, "Peer metadata is unavailable", %{reason: inspect(reason)}}
    end
  end

  defp derp_map_check do
    urls = Settings.get_core_derp_map_urls()

    case {urls, DerpMapCache.get()} do
      {[], _} -> {:ok, %{core_map_configured: false}}
      {_, nil} -> {:warn, "Core DERP map is configured but not cached yet", %{configured_sources: length(urls)}}
      {_, map} -> {:ok, %{configured_sources: length(urls), regions: map |> Map.get("Regions", %{}) |> map_size()}}
    end
  end

  defp passed_check(name, duration_ms, details \\ %{}), do: check(name, :pass, duration_ms, nil, details)
  defp warned_check(name, duration_ms, summary, details), do: check(name, :warn, duration_ms, summary, details)
  defp failed_check(name, summary), do: failed_check(name, summary, 0, %{})
  defp failed_check(name, summary, duration_ms), do: failed_check(name, summary, duration_ms, %{})
  defp failed_check(name, summary, duration_ms, details), do: check(name, :fail, duration_ms, summary, details)

  defp check(name, status, duration_ms, summary, details) do
    %{
      "name" => name,
      "status" => Atom.to_string(status),
      "duration_ms" => duration_ms,
      "summary" => summary,
      "details" => details
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp overall_status(results) do
    cond do
      Enum.any?(results, &(&1["status"] == "fail")) -> "fail"
      Enum.any?(results, &(&1["status"] == "warn")) -> "warn"
      true -> "pass"
    end
  end

  defp sanitize_info(info) when is_map(info) do
    Map.new(info, fn {key, value} -> {to_string(key), sanitize_value(value)} end)
  end

  defp sanitize_info(info) when is_list(info), do: %{"items" => Enum.map(info, &sanitize_value/1)}
  defp sanitize_info(info), do: %{"value" => sanitize_value(info)}

  defp sanitize_value(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp sanitize_value(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} -> {to_string(key), sanitize_value(nested_value)} end)
  end

  defp sanitize_value(value) when is_list(value), do: Enum.map(value, &sanitize_value/1)
  defp sanitize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp sanitize_value(value) when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value), do: value
  defp sanitize_value(value), do: inspect(value)
end
