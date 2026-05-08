# edge_agent/lib/edge_agent/vpn/derp_map_cache.ex
defmodule EdgeAgent.Vpn.DerpMapCache do
  @moduledoc """
  Periodic cache for the DERP map fetched from the configured map server.

  Fetches the DERP map JSON from `derp_map_url` (stored in settings) on startup
  and on a recurring interval (default 5 minutes, configurable via
  `DERP_MAP_REFRESH_INTERVAL_MS`). Serves the cached result instantly to the
  reflection endpoint.

  ## Warm-up behaviour

  On startup the cache hasn't fetched yet, so the first refresh interval is kept
  short (5 s) and doubles on each failed or unconfigured attempt until the
  configured stable interval is reached. Once the map is successfully fetched the
  interval jumps straight to the stable value, stopping the acceleration.

  This means:
  - Fresh agent: retries quickly (5 s → 10 s → 20 s → … → stable)
  - Already cached: stays at the stable interval without churn

  ## Other behaviour

  If `derp_map_url` is nil (not configured), the cache holds nil and the endpoint
  returns an empty regions map — netclient skips the overlay and uses Tailscale fallback.

  If a fetch fails, the last known good cache is kept. The map server URL is re-read
  from settings on every fetch cycle, so re-registration with a new URL takes effect
  within one refresh interval without a restart.
  """

  use GenServer

  alias EdgeAgent.Settings

  require Logger

  @warmup_interval_ms 5_000

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
    stable_ms = Application.get_env(:edge_agent, :derp_map_refresh_interval_ms, to_timeout(minute: 5))
    # If the configured interval is shorter than the warmup start, skip warmup entirely.
    initial_ms = min(@warmup_interval_ms, stable_ms)

    # Fetch on the first message rather than synchronously in init/1 so the
    # supervision tree (and the HTTP endpoint that boots after this cache)
    # don't block on a slow / unreachable DERP map server. Until the first
    # fetch lands, `get/0` returns nil and the reflection endpoint serves
    # an empty regions map — same behaviour the warmup path produced before.
    schedule_refresh(0)
    {:ok, %{map: nil, interval_ms: initial_ms, stable_ms: stable_ms}}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state.map, state}
  end

  @impl true
  def handle_info(:refresh, state) do
    {map, next_ms} = fetch_and_next_interval(state.map, state.interval_ms, state.stable_ms)
    schedule_refresh(next_ms)
    {:noreply, %{state | map: map, interval_ms: next_ms}}
  end

  # =============================================================================
  # Private
  # =============================================================================

  defp schedule_refresh(interval_ms) do
    Process.send_after(self(), :refresh, interval_ms)
  end

  # Returns {map, next_interval_ms}. The pure decision lives in
  # next_state/4; this wrapper handles the impure fetch and the warmup-tick
  # log line (fired on every failed tick before we reach stable cadence).
  defp fetch_and_next_interval(current_map, current_ms, stable_ms) do
    fetch_result = fetch_and_log()
    {map, next_ms} = next_state(fetch_result, current_map, current_ms, stable_ms)

    if is_nil(fetch_result) and next_ms != stable_ms do
      Logger.debug("DerpMapCache: no map yet, next refresh in #{div(next_ms, 1000)} s")
    end

    {map, next_ms}
  end

  @doc false
  # Public for unit testing. Pure interval-doubling logic separated from the
  # impure fetch/log path:
  #   - On success (fetch returned a map): jump straight to stable_ms (we
  #     have data, no need to rush future fetches).
  #   - On failure (fetch returned nil): keep the previous map, double the
  #     current interval, capped at stable_ms.
  @spec next_state(map() | nil, map() | nil, pos_integer(), pos_integer()) ::
          {map() | nil, pos_integer()}
  def next_state(nil, current_map, current_ms, stable_ms) do
    {current_map, min(current_ms * 2, stable_ms)}
  end

  def next_state(map, _current_map, _current_ms, stable_ms) do
    {map, stable_ms}
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

  @doc false
  # Public for unit testing. A 200 response counts as a successful fetch
  # only if it carries a non-empty `"Regions"` map. Empty/missing regions
  # mean the map server has nothing to overlay; we treat that as a failed
  # fetch so the warmup logic keeps trying.
  @spec map_has_regions?(term()) :: boolean()
  def map_has_regions?(%{"Regions" => regions}) when map_size(regions) > 0, do: true
  def map_has_regions?(_), do: false
end
