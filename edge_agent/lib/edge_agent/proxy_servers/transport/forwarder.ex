# edge_agent/lib/edge_agent/proxy_servers/transport/forwarder.ex
defmodule EdgeAgent.ProxyServers.Transport.Forwarder do
  @moduledoc """
  Bidirectional TCP forwarder with half-close semantics and graceful drain.

  One `forward/3` call starts two unidirectional loops (client→target, target→client).
  Each loop terminates on its source EOF by calling `:gen_tcp.shutdown(dst, :write)`
  on the destination, so the peer sees a proper FIN without losing in-flight data
  in the opposite direction.

  Deadlines:
    * Per-read idle timeout (`Config.recv_timeout/0`)
    * Total tunnel lifetime (`Config.tunnel_total_timeout/0`)
    * Drain grace: if the coordinator receives `{:drain, grace_ms}`, a new
      deadline is set at `now + grace_ms`.

  Byte counters are accumulated per direction and emitted as
  `[:edge_agent, :proxy, :tunnel, :closed]` telemetry when both loops finish.
  """

  alias EdgeAgent.ProxyServers.Config

  require Logger

  @type metadata :: map()

  @doc """
  Start bidirectional forwarding between `client_socket` and `target_socket`.

  Transfers ownership of both sockets to the spawned forwarder processes;
  the caller must not `recv` on either after this returns.

  Blocks until both directions complete or a deadline fires. The caller process
  may receive `{:drain, grace_ms}` while blocked — when that happens the
  forwarder finishes in-flight work within the grace window.
  """
  @spec forward(:gen_tcp.socket(), :gen_tcp.socket(), metadata()) :: :ok
  def forward(client_socket, target_socket, metadata \\ %{}) do
    coordinator = self()
    start = System.monotonic_time(:millisecond)
    deadline = start + Config.tunnel_total_timeout()

    up = spawn_link(fn -> run(client_socket, target_socket, coordinator, deadline) end)
    :gen_tcp.controlling_process(client_socket, up)

    down = spawn_link(fn -> run(target_socket, client_socket, coordinator, deadline) end)
    :gen_tcp.controlling_process(target_socket, down)

    wait_for_both(client_socket, target_socket, up, down, start, deadline, metadata)
  end

  defp wait_for_both(client_socket, target_socket, up, down, start, deadline, metadata) do
    do_wait(client_socket, target_socket, up, down, %{up: nil, down: nil}, start, deadline, metadata)
  end

  defp do_wait(client_socket, target_socket, up, down, state, start, deadline, metadata) do
    timeout_ms = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:forwarder_done, ^up, bytes} ->
        maybe_finish(client_socket, target_socket, up, down, Map.put(state, :up, bytes), start, deadline, metadata)

      {:forwarder_done, ^down, bytes} ->
        maybe_finish(client_socket, target_socket, up, down, Map.put(state, :down, bytes), start, deadline, metadata)

      {:drain, grace_ms} ->
        new_deadline = min(deadline, System.monotonic_time(:millisecond) + grace_ms)
        _ = :gen_tcp.shutdown(target_socket, :write)
        do_wait(client_socket, target_socket, up, down, state, start, new_deadline, Map.put(metadata, :draining, true))
    after
      timeout_ms ->
        Process.exit(up, :tunnel_deadline)
        Process.exit(down, :tunnel_deadline)
        :gen_tcp.close(client_socket)
        :gen_tcp.close(target_socket)

        reason = if Map.get(metadata, :draining), do: :drain_timeout, else: :deadline

        emit_closed(
          Map.get(state, :up, 0),
          Map.get(state, :down, 0),
          System.monotonic_time(:millisecond) - start,
          Map.put(metadata, :reason, reason)
        )

        :ok
    end
  end

  defp maybe_finish(client_socket, target_socket, up, down, %{up: u, down: d} = _state, start, _deadline, metadata)
       when is_integer(u) and is_integer(d) do
    send(up, :stop)
    send(down, :stop)
    :gen_tcp.close(client_socket)
    :gen_tcp.close(target_socket)
    emit_closed(u, d, System.monotonic_time(:millisecond) - start, metadata)
    :ok
  end

  defp maybe_finish(client_socket, target_socket, up, down, state, start, deadline, metadata) do
    do_wait(client_socket, target_socket, up, down, state, start, deadline, metadata)
  end

  defp emit_closed(bytes_up, bytes_down, duration_ms, metadata) do
    :telemetry.execute(
      [:edge_agent, :proxy, :tunnel, :closed],
      %{bytes_up: bytes_up, bytes_down: bytes_down, duration_ms: duration_ms},
      metadata
    )
  end

  defp run(src, dst, coordinator, deadline) do
    bytes = forward_loop(src, dst, 0, deadline)
    send(coordinator, {:forwarder_done, self(), bytes})
    # Park so the process doesn't exit — it owns `src` and exiting would
    # close it, cutting off the opposite direction that still needs to write.
    receive do
      :stop -> :ok
    end
  end

  defp forward_loop(src, dst, bytes, deadline) do
    idle = Config.recv_timeout()
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)
    timeout = min(idle, remaining)

    case :gen_tcp.recv(src, 0, timeout) do
      {:ok, data} ->
        case :gen_tcp.send(dst, data) do
          :ok -> forward_loop(src, dst, bytes + byte_size(data), deadline)
          {:error, _reason} -> bytes
        end

      {:error, :closed} ->
        _ = :gen_tcp.shutdown(dst, :write)
        bytes

      {:error, _reason} ->
        bytes
    end
  end
end
