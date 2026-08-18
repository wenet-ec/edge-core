# edge_admin/lib/edge_admin_proxy/admin_tunnel/client.ex
defmodule EdgeAdminProxy.AdminTunnel.Client do
  @moduledoc "Opens the raw TCP data channel to the owning Admin."

  alias EdgeAdminProxy.AdminTunnel.Config
  alias EdgeAdminProxy.AdminTunnel.Protocol
  alias EdgeAdminProxy.Config, as: ProxyConfig

  @spec connect(String.t(), String.t(), 1..65_535) :: {:ok, :gen_tcp.socket()} | {:error, term()}
  def connect(admin_hostname, target_host, target_port) do
    connect_addresses(resolve_addresses(admin_hostname), target_host, target_port)
  end

  defp connect_addresses([], _target_host, _target_port), do: {:error, :admin_unreachable}

  defp connect_addresses([{family, address} | rest], target_host, target_port) do
    opts = [:binary, family, packet: :raw, active: false, reuseaddr: true]

    case :gen_tcp.connect(address, Config.port(), opts, ProxyConfig.connection_timeout()) do
      {:ok, socket} ->
        case handshake(socket, target_host, target_port) do
          :ok ->
            {:ok, socket}

          {:error, reason} ->
            :gen_tcp.close(socket)

            case connect_addresses(rest, target_host, target_port) do
              {:error, _} -> {:error, reason}
              success -> success
            end
        end

      {:error, _reason} ->
        connect_addresses(rest, target_host, target_port)
    end
  end

  defp resolve_addresses(hostname) do
    Enum.flat_map([:inet, :inet6], fn family ->
      case :inet.getaddrs(String.to_charlist(hostname), family) do
        {:ok, addresses} -> Enum.map(addresses, &{family, &1})
        {:error, _reason} -> []
      end
    end)
  end

  defp handshake(socket, target_host, target_port) do
    with :ok <- :gen_tcp.send(socket, Protocol.build_handshake(Config.secret(), target_host, target_port)),
         {:ok, <<1, 0::16>>} <- :gen_tcp.recv(socket, 3, ProxyConfig.handshake_timeout()) do
      :ok
    else
      {:ok, <<0, _::16>>} -> {:error, :tunnel_rejected}
      {:ok, _} -> {:error, :invalid_handshake}
      {:error, reason} -> {:error, reason}
    end
  end
end
