# edge_agent/lib/edge_agent/commands/command_execution_output.ex
defmodule EdgeAgent.Commands.CommandExecutionOutput do
  @moduledoc "Pure output-size protection for local command executions."

  @max_output_bytes 1_024 * 1_024
  @half_output_bytes div(@max_output_bytes, 2)

  @doc "Truncates output to 1 MB while preserving its beginning and end."
  @spec truncate(String.t() | nil) :: String.t() | nil
  def truncate(nil), do: nil

  def truncate(output) when is_binary(output) do
    if byte_size(output) <= @max_output_bytes do
      output
    else
      head = binary_part(output, 0, @half_output_bytes)
      tail = binary_part(output, byte_size(output) - @half_output_bytes, @half_output_bytes)
      omitted = byte_size(output) - @max_output_bytes
      "#{head}\n...[truncated: #{omitted} bytes omitted]...\n#{tail}"
    end
  end
end
