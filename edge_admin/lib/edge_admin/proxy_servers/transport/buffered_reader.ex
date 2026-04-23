# edge_admin/lib/edge_admin/proxy_servers/transport/buffered_reader.ex
defmodule EdgeAdmin.ProxyServers.Transport.BufferedReader do
  @moduledoc """
  Helpers for reading a framed protocol message from either:

    * a passive `:gen_tcp` socket (`read_passive/3`)
    * an active `{:tcp, socket, data}` message mailbox (`read_active/3`)

  Both functions take a `parser` function returning one of `{:ok, value, rest}`,
  `{:need_more, required}`, or `{:error, reason}`. They loop until the parser
  commits to a value or errors.

  Why this exists: the previous active-mode SOCKS5 reader assumed each
  `{:tcp, socket, data}` delivery contained exactly one protocol record, which
  is not a TCP guarantee.
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

  @doc """
  Read from the current process's mailbox (active socket) until `parser` yields.
  Returns `{:ok, value, leftover_buffer}`.
  """
  @spec read_active(:gen_tcp.socket(), parser(t), timeout()) :: {:ok, t, binary()} | {:error, term()}
        when t: var
  def read_active(socket, parser, timeout) do
    read_active(socket, parser, timeout, <<>>)
  end

  defp read_active(socket, parser, timeout, buf) do
    case parser.(buf) do
      {:ok, value, rest} ->
        {:ok, value, rest}

      {:error, _} = err ->
        err

      {:need_more, _} ->
        receive do
          {:tcp, ^socket, data} ->
            read_active(socket, parser, timeout, buf <> data)

          {:tcp_closed, ^socket} ->
            {:error, :closed}

          {:tcp_error, ^socket, reason} ->
            {:error, reason}
        after
          timeout -> {:error, :timeout}
        end
    end
  end
end
