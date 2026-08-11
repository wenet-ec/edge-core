# edge_agent/lib/edge_agent/ssh_server/channel/pty.ex
defmodule EdgeAgent.SshServer.Channel.Pty do
  @moduledoc "Pure PTY, shell-environment, and exit-status helpers."

  @default_term ~c"xterm"

  @spec build_shell_env(map(), String.t(), String.t()) :: [{charlist(), charlist() | false}]
  def build_shell_env(pty, username, node_id) do
    [
      {~c"TERM", pty.term},
      {~c"USER", to_charlist(username)},
      {~c"EDGE_NODE_ID", to_charlist(node_id)},
      {~c"LANG", ~c"C.UTF-8"},
      {~c"LANGUAGE", false},
      {~c"LC_ALL", false}
    ]
  end

  @spec build_shell_run_opts(map(), [{charlist(), charlist() | false}]) :: keyword()
  def build_shell_run_opts(pty, env) do
    [
      {:pty, pty.modes},
      :pty_echo,
      :stdin,
      {:stdout, self()},
      {:stderr, :stdout},
      {:winsz, {pty.rows, pty.cols}},
      {:env, env},
      :monitor,
      :kill_group
    ]
  end

  @spec pty_term(term()) :: charlist()
  def pty_term(""), do: @default_term
  def pty_term(term) when is_list(term) and term != [], do: term
  def pty_term(term) when is_binary(term) and byte_size(term) > 0, do: to_charlist(term)
  def pty_term(_), do: @default_term

  @spec nonzero_or(term(), pos_integer()) :: pos_integer()
  def nonzero_or(0, default), do: default
  def nonzero_or(n, _default) when is_integer(n) and n > 0, do: n
  def nonzero_or(_, default), do: default

  @spec sanitize_pty_modes(term()) :: [{atom(), integer() | boolean()}]
  def sanitize_pty_modes(modes) when is_list(modes) do
    Enum.filter(modes, fn
      {key, value} when is_atom(key) and (is_integer(value) or is_boolean(value)) -> true
      _ -> false
    end)
  end

  def sanitize_pty_modes(_), do: []

  @spec exit_status_from_wait(integer()) :: 0..255
  def exit_status_from_wait(status) when is_integer(status) do
    if Bitwise.band(status, 0x7F) == 0 do
      status |> Bitwise.bsr(8) |> Bitwise.band(0xFF)
    else
      Bitwise.band(status, 0x7F)
    end
  end
end
