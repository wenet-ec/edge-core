# edge_agent/test/edge_agent/ssh_server/channel_test.exs
defmodule EdgeAgent.SshServer.ChannelTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.SshServer.Channel

  # ---------------------------------------------------------------------------
  # pty_term/1 — normalises the `TERM` value coming out of the SSH pty-req.
  # The Erlang :ssh app delivers it as a charlist for well-formed clients,
  # but the spec also allows empty/missing values. erlexec wants a non-empty
  # charlist; an empty TERM reaches the child as `TERM=` and breaks anything
  # that consults terminfo (less, nano, top, …).
  # ---------------------------------------------------------------------------

  describe "pty_term/1" do
    test "passes a non-empty charlist through unchanged" do
      assert Channel.pty_term(~c"xterm-256color") == ~c"xterm-256color"
    end

    test "converts a non-empty binary to a charlist" do
      assert Channel.pty_term("xterm") == ~c"xterm"
    end

    test "falls back to xterm for an empty binary" do
      assert Channel.pty_term("") == ~c"xterm"
    end

    test "falls back to xterm for an empty charlist" do
      assert Channel.pty_term([]) == ~c"xterm"
    end

    test "falls back to xterm for nil or garbage" do
      assert Channel.pty_term(nil) == ~c"xterm"
      assert Channel.pty_term(:vt100) == ~c"xterm"
      assert Channel.pty_term(123) == ~c"xterm"
    end
  end

  # ---------------------------------------------------------------------------
  # nonzero_or/2 — RFC 4254 §6.2 says a zero in char_w/row_h means "use the
  # pixel dimensions instead." We don't honor pixel dimensions, so zero must
  # collapse to a sane default. A 0×0 pty reaches the child as a terminal
  # with no rows or columns and full-screen programs render to an invisible
  # buffer.
  # ---------------------------------------------------------------------------

  describe "nonzero_or/2" do
    test "passes a positive integer through unchanged" do
      assert Channel.nonzero_or(80, 24) == 80
      assert Channel.nonzero_or(1, 24) == 1
    end

    test "falls back when the value is zero" do
      assert Channel.nonzero_or(0, 24) == 24
    end

    test "falls back for negatives and non-integers" do
      assert Channel.nonzero_or(-1, 24) == 24
      assert Channel.nonzero_or(nil, 80) == 80
      assert Channel.nonzero_or("not a number", 80) == 80
    end
  end

  # ---------------------------------------------------------------------------
  # sanitize_pty_modes/1 — Erlang's :ssh app gives the pty-req termios opcodes
  # as `[{atom, integer}, ...]` for opcodes it knows about, and `[{byte, _},
  # ...]` for opcodes it doesn't. erlexec's strict validator rejects the
  # WHOLE list if any entry has a non-atom key or non-integer/boolean value,
  # so we drop the unknown-opcode entries before passing through. Forgetting
  # this filter means a single unknown opcode (e.g. a new RFC extension)
  # makes shell startup fail entirely.
  # ---------------------------------------------------------------------------

  describe "sanitize_pty_modes/1" do
    test "keeps {atom, integer} entries (known opcodes)" do
      modes = [{:vintr, 3}, {:vquit, 28}, {:opost, 1}]
      assert Channel.sanitize_pty_modes(modes) == modes
    end

    test "keeps {atom, boolean} entries (mode flags)" do
      modes = [{:echo, true}, {:icanon, false}]
      assert Channel.sanitize_pty_modes(modes) == modes
    end

    test "drops {integer, _} entries (numeric opcodes the ssh app didn't recognise)" do
      assert Channel.sanitize_pty_modes([{53, 1}, {:vintr, 3}, {200, 0}]) == [{:vintr, 3}]
    end

    test "drops entries with non-integer/boolean values" do
      assert Channel.sanitize_pty_modes([{:echo, :on}, {:vintr, 3}]) == [{:vintr, 3}]
    end

    test "returns [] for non-list input" do
      assert Channel.sanitize_pty_modes(nil) == []
      assert Channel.sanitize_pty_modes(%{}) == []
      assert Channel.sanitize_pty_modes("modes") == []
    end

    test "returns [] for the empty list" do
      assert Channel.sanitize_pty_modes([]) == []
    end
  end

  # ---------------------------------------------------------------------------
  # exit_status_from_wait/1 — erlexec hands us the raw 16-bit status from
  # POSIX wait(2): the high byte is the exit code if the low 7 bits are
  # zero (normal exit), otherwise the low 7 bits are the signal number that
  # killed the process. SSH wants a plain 0..255. If we forgot the shift,
  # `exit 1` would surface to the SSH client as exit status 256 — which the
  # SSH protocol can't even represent.
  # ---------------------------------------------------------------------------

  describe "exit_status_from_wait/1" do
    test "decodes a normal exit-with-status: high byte is the code" do
      # bash `exit 0`
      assert Channel.exit_status_from_wait(0) == 0
      # bash `exit 1` → wait status 256
      assert Channel.exit_status_from_wait(256) == 1
      # bash `exit 127` → wait status 32_512
      assert Channel.exit_status_from_wait(32_512) == 127
      # bash `exit 255` → wait status 65_280
      assert Channel.exit_status_from_wait(65_280) == 255
    end

    test "decodes a signal exit: low 7 bits are the signal number" do
      # killed by SIGTERM (15) → wait status 15
      assert Channel.exit_status_from_wait(15) == 15
      # killed by SIGKILL (9) → wait status 9 (137 on the shell, but raw is 9)
      assert Channel.exit_status_from_wait(9) == 9
      # killed by SIGTERM with core flag set (0x80 | 15 = 0x8F) still resolves to 15
      assert Channel.exit_status_from_wait(0x8F) == 15
    end

    test "always returns a value in the 0..255 SSH range" do
      for n <- [0, 256, 32_512, 65_280, 15, 9, 0x7F, 0xFFFF] do
        result = Channel.exit_status_from_wait(n)
        assert result in 0..255, "wait status #{n} produced out-of-range #{result}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # build_shell_env/3 — the env we hand to host_pty_spawn when spawning the
  # SSH shell. The shell runs on the host (bash --login -i inside the host's
  # mount namespace), so the host's /etc/profile + ~/.bashrc set PATH, HOME,
  # SHELL. We forward only what the host can't infer:
  #   * `TERM` from the client's pty-req (else nano/less break)
  #   * `USER` from authentication
  #   * `EDGE_NODE_ID` for any host-side prompt customisation
  # And explicitly override locale to keep the container's en_US.UTF-8 from
  # leaking onto a host that hasn't generated that locale.
  # ---------------------------------------------------------------------------

  describe "build_shell_env/3" do
    test "forwards TERM from the pty-req and includes identity vars" do
      pty = %{term: ~c"xterm-256color", cols: 80, rows: 24, modes: []}
      env = Channel.build_shell_env(pty, "admin", "node-abc-12345")

      assert {~c"TERM", ~c"xterm-256color"} in env
      assert {~c"USER", ~c"admin"} in env
      assert {~c"EDGE_NODE_ID", ~c"node-abc-12345"} in env
    end

    test "does not leak container-side HOME/SHELL/PATH" do
      pty = %{term: ~c"xterm", cols: 80, rows: 24, modes: []}
      env = Channel.build_shell_env(pty, "x", "y")
      keys = for {k, _} <- env, do: k

      # bash --login on the host sources /etc/profile and ~/.bashrc which
      # set these. Leaking container values would mask the host's real env.
      for forbidden <- [~c"HOME", ~c"SHELL", ~c"PATH"] do
        refute forbidden in keys, "leaked container env var #{forbidden}"
      end
    end

    test "forces LANG to C.UTF-8 and unsets LANGUAGE / LC_ALL" do
      # The container's Dockerfile sets LANG=en_US.UTF-8, which leaks through
      # erlexec's env inheritance. Most hosts haven't generated en_US.UTF-8,
      # so bash prints `cannot change locale` warnings on every shell startup.
      # Pinning C.UTF-8 (always available on glibc) avoids that, and unsetting
      # LANGUAGE / LC_ALL (via `false`) stops them fighting LANG.
      pty = %{term: ~c"xterm", cols: 80, rows: 24, modes: []}
      env = Channel.build_shell_env(pty, "x", "y")

      assert {~c"LANG", ~c"C.UTF-8"} in env
      assert {~c"LANGUAGE", false} in env
      assert {~c"LC_ALL", false} in env
    end
  end

  # ---------------------------------------------------------------------------
  # build_shell_run_opts/2 — the keyword list we hand to :exec.run/2. The
  # critical opts are :pty (real terminal — the whole reason this refactor
  # exists), {:winsz, {rows, cols}} (dimensions from the pty-req), and
  # :monitor (so we receive :DOWN when bash exits). A drift here is the bug
  # class that originally caused nano not to save.
  # ---------------------------------------------------------------------------

  describe "build_shell_run_opts/2" do
    test "requests a real pty with the modes from pty-req" do
      pty = %{term: ~c"xterm", cols: 100, rows: 30, modes: [{:vintr, 3}]}
      opts = Channel.build_shell_run_opts(pty, [])
      assert {:pty, [{:vintr, 3}]} in opts
    end

    test "passes the SSH-supplied dimensions as winsz {rows, cols}" do
      pty = %{term: ~c"xterm", cols: 100, rows: 30, modes: []}
      opts = Channel.build_shell_run_opts(pty, [])
      assert {:winsz, {30, 100}} in opts
    end

    test "always enables :monitor so we observe the child's exit" do
      pty = %{term: ~c"xterm", cols: 80, rows: 24, modes: []}
      opts = Channel.build_shell_run_opts(pty, [])
      assert :monitor in opts
    end

    test "always enables :stdin and :pty_echo (no PTY without these)" do
      pty = %{term: ~c"xterm", cols: 80, rows: 24, modes: []}
      opts = Channel.build_shell_run_opts(pty, [])
      assert :stdin in opts
      assert :pty_echo in opts
    end

    test "always sets :kill_group so the whole pty session dies on disconnect" do
      pty = %{term: ~c"xterm", cols: 80, rows: 24, modes: []}
      opts = Channel.build_shell_run_opts(pty, [])
      assert :kill_group in opts
    end
  end
end
