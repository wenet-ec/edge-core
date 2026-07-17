# edge_agent/lib/edge_agent/diagnostics/wireguard_interface.ex
defmodule EdgeAgent.Diagnostics.WireguardInterface do
  @moduledoc false

  @interface "netmaker"

  @spec check() :: {:ok, map()} | {:warn, String.t(), map()} | {:error, String.t(), map()}
  def check do
    with {:ok, [link]} <- ip_json(["-j", "link", "show", "dev", @interface]),
         {:ok, [address]} <- ip_json(["-j", "address", "show", "dev", @interface]),
         {:ok, routes} <- ip_json(["-j", "route", "show", "dev", @interface]) do
      assess(link, address, routes)
    else
      {:ok, []} -> {:error, "WireGuard interface is missing", %{interface: @interface}}
      {:error, reason} -> {:error, "Could not inspect WireGuard interface", %{interface: @interface, reason: reason}}
    end
  end

  @doc false
  @spec assess(map(), map(), [map()]) :: {:ok, map()} | {:warn, String.t(), map()} | {:error, String.t(), map()}
  def assess(link, address, routes) do
    flags = Map.get(link, "flags", [])

    details = %{
      interface: @interface,
      state: link |> Map.get("operstate", "unknown") |> String.downcase(),
      flags: flags,
      addresses: addresses(address),
      routes: routes(routes)
    }

    cond do
      "UP" not in flags ->
        {:error, "WireGuard interface is not up", details}

      details.addresses == [] ->
        {:error, "WireGuard interface has no VPN address", details}

      details.routes == [] ->
        {:warn, "WireGuard interface has no routes", details}

      true ->
        {:ok, details}
    end
  end

  defp ip_json(args) do
    case System.cmd("ip", args, stderr_to_stdout: true) do
      {output, 0} ->
        case JSON.decode(output) do
          {:ok, result} when is_list(result) -> {:ok, result}
          {:ok, _result} -> {:error, "unexpected ip output"}
          {:error, reason} -> {:error, "invalid ip JSON: #{Exception.message(reason)}"}
        end

      {output, _exit_code} ->
        {:error, String.trim(output)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp addresses(address) do
    address
    |> Map.get("addr_info", [])
    |> Enum.flat_map(fn
      %{"local" => local, "prefixlen" => prefixlen, "scope" => "global"} when is_integer(prefixlen) ->
        ["#{local}/#{prefixlen}"]

      _ ->
        []
    end)
  end

  defp routes(routes) do
    Enum.map(routes, fn route ->
      %{
        destination: Map.get(route, "dst", "default"),
        gateway: Map.get(route, "gateway"),
        protocol: Map.get(route, "protocol")
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
    end)
  end
end
