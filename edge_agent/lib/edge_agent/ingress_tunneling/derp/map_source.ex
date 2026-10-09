# edge_agent/lib/edge_agent/ingress_tunneling/derp/map_source.ex
defmodule EdgeAgent.IngressTunneling.Derp.MapSource do
  @moduledoc "Loads the map used by Edge Ingress, falling back to Tailscale when no Core map is cached."

  @public_map_url "https://login.tailscale.com/derpmap/default"

  @spec fetch(map() | nil) :: {:ok, map()} | {:error, term()}
  def fetch(%{"Regions" => regions} = map) when is_map(regions) and map_size(regions) > 0, do: {:ok, map}

  def fetch(_core_map) do
    case Req.get(@public_map_url, receive_timeout: 5_000, connect_options: [timeout: 3_000]) do
      {:ok, %{status: 200, body: %{"Regions" => regions} = map}}
      when is_map(regions) and map_size(regions) > 0 ->
        {:ok, map}

      {:ok, %{status: 200}} ->
        {:error, :empty_regions}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
