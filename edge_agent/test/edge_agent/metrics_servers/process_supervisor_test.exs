# edge_agent/test/edge_agent/metrics_servers/process_supervisor_test.exs
defmodule EdgeAgent.MetricsServers.ProcessSupervisorTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.MetricsServers.ProcessSupervisor

  describe "parse_ss_output/2" do
    test "extracts the PID of a process matching the configured binary" do
      output = """
      LISTEN 0  128  0.0.0.0:49100  0.0.0.0:*  users:(("node_exporter",pid=8348,fd=3))
      """

      assert ProcessSupervisor.parse_ss_output(output, "node_exporter") == {:ok, 8348}
    end

    test "matches a 15-char-truncated /proc/PID/comm name (Linux comm limit)" do
      # `ss` shows the kernel's TASK_COMM_LEN-truncated name. Real-world
      # example: "prometheus_wireguard_exporter" → "prometheus_wire".
      output = """
      LISTEN 0  128  *:49586  *:*  users:(("prometheus_wire",pid=8720,fd=6))
      """

      assert ProcessSupervisor.parse_ss_output(output, "prometheus_wireguard_exporter") ==
               {:ok, 8720}
    end

    test "returns :not_found when no socket matches the binary name" do
      output = """
      LISTEN 0  128  0.0.0.0:49100  0.0.0.0:*  users:(("something_else",pid=999,fd=3))
      """

      assert ProcessSupervisor.parse_ss_output(output, "node_exporter") == {:error, :not_found}
    end

    test "returns :not_found on empty output (no listener on the port)" do
      assert ProcessSupervisor.parse_ss_output("", "node_exporter") == {:error, :not_found}
    end

    test "picks the matching line when multiple sockets share the search" do
      output = """
      LISTEN 0  128  0.0.0.0:49100  0.0.0.0:*  users:(("docker-proxy",pid=111,fd=7))
      LISTEN 0  128  0.0.0.0:49100  0.0.0.0:*  users:(("node_exporter",pid=8348,fd=3))
      """

      assert ProcessSupervisor.parse_ss_output(output, "node_exporter") == {:ok, 8348}
    end
  end

  describe "parse_pgrep_output/1" do
    test "returns the PID for single-line output" do
      assert ProcessSupervisor.parse_pgrep_output("8348\n") == {:ok, 8348}
    end

    test "takes the first valid PID from multi-line output" do
      # Defends against the production bug: under `pid: host`, pgrep can
      # match both the real exporter and the shell command searching for
      # it, returning multiple PIDs. The old `{pid, ""}` parse failed.
      assert ProcessSupervisor.parse_pgrep_output("8348\n102647\n") == {:ok, 8348}
    end

    test "skips non-numeric leading lines and returns the first PID" do
      assert ProcessSupervisor.parse_pgrep_output("garbage\n8348\n") == {:ok, 8348}
    end

    test "returns :invalid_pid when no line parses as an integer" do
      assert ProcessSupervisor.parse_pgrep_output("garbage\nmorenoise\n") ==
               {:error, :invalid_pid}
    end

    test "returns :invalid_pid on empty input" do
      assert ProcessSupervisor.parse_pgrep_output("") == {:error, :invalid_pid}
    end
  end
end
