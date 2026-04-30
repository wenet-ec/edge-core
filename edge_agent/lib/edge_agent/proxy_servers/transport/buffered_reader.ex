# edge_agent/lib/edge_agent/proxy_servers/transport/buffered_reader.ex
defmodule EdgeAgent.ProxyServers.Transport.BufferedReader do
  @moduledoc """
  Helper for reading a framed protocol message from a passive `:gen_tcp` socket.

  Takes a `parser` function returning one of `{:ok, value, rest}`,
  `{:need_more, required}`, or `{:error, reason}`. Loops until the parser
  commits to a value or errors.
  """

  @type parser(t) :: (binary() -> {:ok, t, binary()} | {:need_more, non_neg_integer()} | {:error, term()})

  @doc """
  Read from a passive socket until `parser` yields a value or errors.
  Returns `{:ok, value, leftover_buffer}` so the caller can chain subsequent reads.
  """
  @spec read_passive(:gen_tcp.socket(), parser(t), timeout()) :: {:ok, t, binary()} | {:error, term()}
        when t: var
  def read_passive(socket, parser, timeout) do
    read_passive(socket, parser, timeout, <<>>)
  end

  defp read_passive(socket, parser, timeout, buf) do
    case parser.(buf) do
      {:ok, value, rest} ->
        {:ok, value, rest}

      {:error, _} = err ->
        err

      {:need_more, _} ->
        case :gen_tcp.recv(socket, 0, timeout) do
          {:ok, data} -> read_passive(socket, parser, timeout, buf <> data)
          {:error, _} = err -> err
        end
    end
  end
end
