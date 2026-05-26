# edge_agent/test/edge_agent/commands/commands_test.exs
defmodule EdgeAgent.CommandsTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.Commands
  alias EdgeAgent.Commands.Schemas.CommandExecution

  # ---------------------------------------------------------------------------
  # categorize_exit_code/1 — exit code → domain category. The codes here are
  # contracts: 124 from `timeout(1)`, 143 from SIGTERM (128+15) used by the
  # cancel path. Drift would mis-classify timeouts as failures or vice versa.
  # ---------------------------------------------------------------------------

  describe "categorize_exit_code/1" do
    test "0 → :success" do
      assert Commands.categorize_exit_code(0) == :success
    end

    test "124 → :timeout (conventional exit code from timeout(1))" do
      assert Commands.categorize_exit_code(124) == :timeout
    end

    test "143 → :cancelled (128 + SIGTERM)" do
      assert Commands.categorize_exit_code(143) == :cancelled
    end

    test "any other positive code → :failure" do
      for code <- [1, 2, 127, 130, 137, 255] do
        assert Commands.categorize_exit_code(code) == :failure,
               "expected #{code} to be :failure"
      end
    end

    test "negative codes → :unknown" do
      assert Commands.categorize_exit_code(-1) == :unknown
      assert Commands.categorize_exit_code(-127) == :unknown
    end

    test "the special codes win over the generic positive branch" do
      # 124 is positive, but the specific clause must fire before the
      # generic exit_code > 0 → :failure. Pin the clause order.
      refute Commands.categorize_exit_code(124) == :failure
      refute Commands.categorize_exit_code(143) == :failure
    end
  end

  # ---------------------------------------------------------------------------
  # build_report_params/1 — wire payload sent back to admin
  # ---------------------------------------------------------------------------

  describe "build_report_params/1" do
    test "produces the documented field set" do
      execution = %CommandExecution{
        status: :completed,
        output: "Linux 6.1.0",
        exit_code: 0,
        completed_at: ~U[2026-04-13 10:00:00Z]
      }

      result = Commands.build_report_params(execution)

      assert result == %{
               status: "completed",
               output: "Linux 6.1.0",
               exit_code: 0,
               completed_at: "2026-04-13T10:00:00Z"
             }
    end

    test "renders completed_at as ISO 8601 when set" do
      execution = %CommandExecution{
        status: :completed,
        completed_at: ~U[2026-04-13 10:00:00Z]
      }

      assert Commands.build_report_params(execution).completed_at == "2026-04-13T10:00:00Z"
    end

    test "preserves nil completed_at" do
      # Pending executions don't have a completion time. The wire field is
      # nil rather than an empty string, so admin can distinguish "not yet
      # completed" from "completed but admin shouldn't render time."
      execution = %CommandExecution{status: :pending, completed_at: nil}
      assert Commands.build_report_params(execution).completed_at == nil
    end

    test "passes through nil output and nil exit_code (pending executions)" do
      execution = %CommandExecution{status: :pending, output: nil, exit_code: nil}
      result = Commands.build_report_params(execution)

      assert result.output == nil
      assert result.exit_code == nil
      assert result.status == "pending"
    end

    test "rendered map contains exactly the documented top-level keys" do
      execution = %CommandExecution{status: :completed}
      result = Commands.build_report_params(execution)

      assert result |> Map.keys() |> Enum.sort() ==
               [:completed_at, :exit_code, :output, :status]
    end

    test "truncates oversized output stored in DB before reporting" do
      # Safety net: rows written before truncation was added (e.g. a 143 MB
      # `du` run) must still be trimmed at report time so the PATCH to admin
      # doesn't exceed the request size limit.
      big = String.duplicate("x", 2 * 1024 * 1024)
      execution = %CommandExecution{status: :completed, output: big, exit_code: 0}
      result = Commands.build_report_params(execution)

      assert byte_size(result.output) < 2 * 1024 * 1024
      assert result.output =~ "[truncated:"
    end
  end

  # ---------------------------------------------------------------------------
  # truncate_output/1 — caps output at 1 MB, keeping head + tail with marker.
  # Contract: nil passthrough, small passthrough, large → trimmed with marker.
  # ---------------------------------------------------------------------------

  describe "truncate_output/1" do
    test "nil passthrough" do
      assert Commands.truncate_output(nil) == nil
    end

    test "output under 1 MB is returned unchanged" do
      small = String.duplicate("a", 512)
      assert Commands.truncate_output(small) == small
    end

    test "output exactly at the 1 MB limit is returned unchanged" do
      at_limit = String.duplicate("a", 1024 * 1024)
      assert Commands.truncate_output(at_limit) == at_limit
    end

    test "output over 1 MB is truncated and contains the marker" do
      big = String.duplicate("a", 2 * 1024 * 1024)
      result = Commands.truncate_output(big)

      assert byte_size(result) < byte_size(big)
      assert result =~ "[truncated:"
    end

    test "truncated output starts with the head of the original" do
      head = String.duplicate("h", 512 * 1024)
      tail = String.duplicate("t", 512 * 1024)
      big = head <> String.duplicate("m", 1024 * 1024) <> tail

      result = Commands.truncate_output(big)

      assert String.starts_with?(result, head)
    end

    test "truncated output ends with the tail of the original" do
      head = String.duplicate("h", 512 * 1024)
      tail = String.duplicate("t", 512 * 1024)
      big = head <> String.duplicate("m", 1024 * 1024) <> tail

      result = Commands.truncate_output(big)

      assert String.ends_with?(result, tail)
    end

    test "marker reports the correct number of omitted bytes" do
      total = 3 * 1024 * 1024
      big = String.duplicate("x", total)
      result = Commands.truncate_output(big)

      omitted = total - 1024 * 1024
      assert result =~ "#{omitted} bytes omitted"
    end

    test "empty string is returned unchanged" do
      assert Commands.truncate_output("") == ""
    end
  end
end
