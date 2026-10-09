# edge_agent/lib/edge_agent/ingress_tunneling/reconciler.ex
defmodule EdgeAgent.IngressTunneling.Reconciler do
  @moduledoc "Reconciles the durable Ingress Tunneling snapshot into the isolated network interface."

  use GenServer

  alias EdgeAgent.IngressTunneling.Configuration
  alias EdgeAgent.IngressTunneling.Derp.MapSource
  alias EdgeAgent.IngressTunneling.Identity
  alias EdgeAgent.IngressTunneling.Runtime
  alias EdgeAgent.Settings
  alias EdgeAgent.Vpn.DerpMapCache

  require Logger

  @retry_interval 10_000
  @refresh_interval to_timeout(minute: 5)

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec reconcile() :: :ok
  def reconcile do
    GenServer.cast(__MODULE__, :reconcile)
  catch
    :exit, _reason -> :ok
  end

  @impl GenServer
  def init(_opts) do
    Process.flag(:trap_exit, true)
    send(self(), :reconcile)
    schedule_refresh()
    {:ok, %{runtime: nil, fingerprint: nil, config_fingerprint: nil, derp_map: nil, retry_timer: nil}}
  end

  @impl GenServer
  def handle_cast(:reconcile, state), do: {:noreply, apply_snapshot(state)}

  @impl GenServer
  def handle_info(:reconcile, state), do: {:noreply, apply_snapshot(state)}

  def handle_info(:refresh, state) do
    send(self(), :reconcile)
    schedule_refresh()
    {:noreply, state}
  end

  def handle_info(:retry, state) do
    {:noreply, apply_snapshot(%{state | retry_timer: nil})}
  end

  def handle_info({port, {:exit_status, status}}, state) when is_port(port) do
    if runtime_port?(state.runtime, port) do
      Logger.warning("Ingress child process exited with status #{status}; reconciling")
      Runtime.stop(state.runtime)
      {:noreply, state |> Map.merge(%{runtime: nil, fingerprint: nil}) |> schedule_retry()}
    else
      {:noreply, state}
    end
  end

  def handle_info({port, {:data, data}}, state) when is_port(port) and is_binary(data) do
    if runtime_port?(state.runtime, port), do: Logger.debug("Ingress child: #{String.trim(data)}")
    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, reason}, state) do
    case reason do
      :normal ->
        {:noreply, state}

      _ ->
        Logger.warning("Ingress transport exited: #{inspect(reason)}")
        Runtime.stop(state.runtime)
        {:noreply, state |> Map.merge(%{runtime: nil, fingerprint: nil}) |> schedule_retry()}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, state), do: Runtime.stop(state.runtime)

  defp apply_snapshot(state) do
    case Settings.get_ingress_tunneling() do
      nil -> stop_runtime(state)
      %{"peers" => []} -> stop_runtime(state)
      ingress_tunneling -> reconcile_snapshot(state, ingress_tunneling)
    end
  end

  defp reconcile_snapshot(state, ingress_tunneling) do
    with {:ok, config} <- Configuration.validate(ingress_tunneling),
         :ok <- Identity.verify_public_key(config["ingress_public_key"]) do
      config_fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary(config))
      state = stop_old_configuration(state, config_fingerprint)

      case MapSource.fetch(DerpMapCache.get()) do
        {:ok, derp_map} ->
          reconcile_with_map(state, config, derp_map, config_fingerprint)

        {:error, reason} ->
          Logger.warning("Ingress DERP map unavailable: #{inspect(reason)}")

          case state.derp_map do
            %{"Regions" => regions} = derp_map when is_map(regions) and map_size(regions) > 0 ->
              state
              |> reconcile_with_map(config, derp_map, config_fingerprint)
              |> schedule_retry()

            _ ->
              schedule_retry(state)
          end
      end
    else
      {:error, reason} ->
        Logger.warning("Ingress configuration could not be applied: #{inspect(reason)}")
        Runtime.stop(state.runtime)
        state |> Map.merge(%{runtime: nil, fingerprint: nil}) |> schedule_retry()
    end
  end

  defp reconcile_with_map(state, config, derp_map, config_fingerprint) do
    fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary({config_fingerprint, derp_map}))

    if state.fingerprint == fingerprint and runtime_alive?(state.runtime) do
      state |> Map.put(:derp_map, derp_map) |> cancel_retry()
    else
      replace_runtime(state, config, derp_map, fingerprint, config_fingerprint)
    end
  end

  defp stop_old_configuration(%{config_fingerprint: current} = state, current), do: state

  defp stop_old_configuration(state, next_fingerprint) do
    Runtime.stop(state.runtime)
    %{state | runtime: nil, fingerprint: nil, config_fingerprint: next_fingerprint}
  end

  defp replace_runtime(state, config, derp_map, fingerprint, config_fingerprint) do
    Runtime.stop(state.runtime)

    case Runtime.start(config, derp_map) do
      {:ok, runtime} ->
        state
        |> cancel_retry()
        |> Map.merge(%{
          runtime: runtime,
          fingerprint: fingerprint,
          config_fingerprint: config_fingerprint,
          derp_map: derp_map
        })

      {:error, reason} ->
        Logger.error("Ingress reconciliation failed: #{inspect(reason)}")

        state
        |> Map.merge(%{runtime: nil, fingerprint: nil, config_fingerprint: config_fingerprint, derp_map: derp_map})
        |> schedule_retry()
    end
  end

  defp stop_runtime(state) do
    Runtime.stop(state.runtime)

    state
    |> cancel_retry()
    |> Map.merge(%{runtime: nil, fingerprint: nil, config_fingerprint: nil, derp_map: nil})
  end

  defp runtime_alive?(nil), do: false
  defp runtime_alive?(%{transport: transport}), do: is_pid(transport) and Process.alive?(transport)

  defp runtime_port?(nil, _port), do: false

  defp runtime_port?(runtime, port) do
    port == runtime.wireguard[:process] or port == runtime.dns
  end

  defp schedule_retry(%{retry_timer: nil} = state) do
    %{state | retry_timer: Process.send_after(self(), :retry, @retry_interval)}
  end

  defp schedule_retry(state), do: state

  defp cancel_retry(%{retry_timer: nil} = state), do: state

  defp cancel_retry(%{retry_timer: timer} = state) do
    Process.cancel_timer(timer)
    %{state | retry_timer: nil}
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval)
end
