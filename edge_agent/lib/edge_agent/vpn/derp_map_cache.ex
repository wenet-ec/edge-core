# edge_agent/lib/edge_agent/vpn/derp_map_cache.ex
defmodule EdgeAgent.Vpn.DerpMapCache do
  @moduledoc """
  Periodic cache for the DERP map fetched from the configured map server.

  Fetches the DERP map JSON from `derp_map_url` (stored in settings) on startup
  and every 5 minutes. Serves the cached result instantly to the reflection endpoint.

  If `derp_map_url` is nil (not configured), the cache holds nil and the endpoint
  returns an empty regions map — netclient skips the overlay and uses Tailscale fallback.

  If a fetch fails, the last known good cache is kept. The map server URL is re-read
  from settings on every fetch cycle, so re-registration with a new URL takes effect
  within one refresh interval without a restart.
  """

  use GenServer

  alias EdgeAgent.Settings

  require Logger

  @refresh_interval to_timeout(minute: 5)

  # =============================================================================
  # Public API
  # =============================================================================

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the cached DERP map as a map, or nil if not yet fetched / not configured.
  """
  @spec get() :: map() | nil
  def get do
    GenServer.call(__MODULE__, :get)
  end

  # =============================================================================
  # GenServer Callbacks
  # =============================================================================

  @impl true
  def init(_opts) do
    map = fetch_and_log()
    schedule_refresh()
    {:ok, %{map: map}}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state.map, state}
  end

  @impl true
  def handle_info(:refresh, state) do
    map = fetch_and_log()
    schedule_refresh()
    {:noreply, %{state | map: map}}
  end

  # =============================================================================
  # Private
  # =============================================================================

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  defp fetch_and_log do
    case Settings.get_derp_map_url() do
      nil ->
        Logger.debug("DerpMapCache: derp_map_url not configured, cache empty")
        nil

      url ->
        case fetch(url) do
          {:ok, map} ->
            Logger.info("DerpMapCache: fetched DERP map from #{url}")
            map

          {:error, reason} ->
            Logger.warning("DerpMapCache: fetch failed from #{url}: #{inspect(reason)}")
            nil
        end
    end
  end

  defp fetch(url) do
    case Req.get(url, receive_timeout: 5_000, connect_options: [timeout: 3_000]) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        if map_has_regions?(body) do
          {:ok, body}
        else
          {:error, :empty_regions}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp map_has_regions?(%{"Regions" => regions}) when map_size(regions) > 0, do: true
  defp map_has_regions?(_), do: false
end
