# nexmaker/lib/nexmaker/cli_parser.ex
defmodule Nexmaker.CliParser do
  @moduledoc """
  Robust parser for netclient CLI output based on actual source code patterns.

  This module implements parsing strategies derived from netclient's Go source code,
  handling all known output formats and error patterns.

  ## Known Output Patterns

  ### `netclient list`
  - Success: JSON array `[{"network":"...","node_id":"...","connected":bool,...}]`
  - No networks: Plain text `"\\nno such network"`
  - Logs: `[netclient] YYYY-MM-DD HH:MM:SS <message>`

  ### `netclient ping -j`
  - Success: JSON object `{"network-name": [{"network":"...","name":"...","address":"...","connected":bool,"latency_ms":int64}]}`
  - No peers: Plain text `"\\nNo peers found"` / `"\\nNo peers matched..."`
  - Error: Plain text `"\\nFailed to ping peers: <error>"`

  ## Parsing Strategy

  1. **Clean logs**: Strip `[netclient]` prefixed lines
  2. **Detect format**: Check for known plain-text patterns first
  3. **Extract JSON**: Use regex to find JSON structures (objects/arrays)
  4. **Validate**: Parse JSON and validate structure matches expected schema
  5. **Return**: Structured result or error

  ## References

  - netclient/functions/list.go (List function)
  - netclient/functions/ping.go (PingPeers function)
  """

  require Logger

  # Known plain-text error/info patterns from netclient source
  @no_network_pattern ~r/no such network/i
  @no_peers_patterns [
    ~r/No peers found/i,
    ~r/No peers matched/i
  ]
  @ping_error_pattern ~r/Failed to ping peers:/i

  @doc """
  Parse `netclient list` output.

  ## Returns
  - `{:ok, networks}` - List of network maps
  - `{:ok, []}` - No networks (plaintext "no such network")
  - `{:error, reason}` - Parse failure

  ## Examples

      iex> parse_list_output("[{\\"network\\":\\"test\\"}]")
      {:ok, [%{"network" => "test"}]}

      iex> parse_list_output("\\nno such network")
      {:ok, []}
  """
  @spec parse_list_output(String.t()) :: {:ok, list()} | {:error, term()}
  def parse_list_output(output) when is_binary(output) do
    # Check for "no such network" pattern first
    if Regex.match?(@no_network_pattern, output) do
      {:ok, []}
    else
      # Clean logs and extract JSON
      case extract_and_parse_json(output, :array) do
        {:ok, networks} when is_list(networks) ->
          {:ok, networks}

        {:ok, _other} ->
          {:error, :expected_array}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Parse `netclient peers -j` output.

  ## Returns
  - `{:ok, peers_data}` - Map with "interface" and "peers" keys
  - `{:ok, %{"peers" => %{}}}` - No peers found (plaintext "No peers found...")
  - `{:error, {:peers_failed, reason}}` - Command-level failure (e.g. HTTP call to fetch peer metadata failed)
  - `{:error, reason}` - Parse failure

  ## Examples

      iex> parse_peers_output("{\\"interface\\":{\\"name\\":\\"nm-0\\"},\\"peers\\":{\\"net\\":[{\\"public_key\\":\\"..\\"}]}}")
      {:ok, %{"interface" => %{"name" => "nm-0"}, "peers" => %{"net" => [...]}}}

      iex> parse_peers_output("[]")
      {:ok, %{"peers" => %{}}}

      iex> parse_peers_output("\\nNo peers found on interface nm-0")
      {:ok, %{"peers" => %{}}}

      iex> parse_peers_output("\\nFailed to get peer information: connection refused")
      {:error, {:peers_failed, "connection refused"}}
  """
  @spec parse_peers_output(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_peers_output(output) when is_binary(output) do
    cond do
      # Check for command-level error (e.g. HTTP call to fetch peer metadata failed)
      # Format: "\nFailed to get peer information: <reason>"
      String.contains?(output, "Failed to get peer information:") ->
        case Regex.run(~r/Failed to get peer information:\s*(.+)/i, output) do
          [_, error_msg] -> {:error, {:peers_failed, String.trim(error_msg)}}
          _ -> {:error, {:peers_failed, "unknown error"}}
        end

      # Check for "No peers found" patterns
      String.contains?(output, "No peers found") ->
        {:ok, %{"peers" => %{}}}

      # Check for empty array
      String.trim(output) == "[]" ->
        {:ok, %{"peers" => %{}}}

      # Parse JSON output
      true ->
        case extract_and_parse_json(output, :object) do
          {:ok, peers_data} when is_map(peers_data) ->
            # Validate structure: must have "peers" key
            if Map.has_key?(peers_data, "peers") do
              {:ok, peers_data}
            else
              {:error, :missing_peers_key}
            end

          # Handle empty array case
          {:error, :no_object_found} ->
            case extract_and_parse_json(output, :array) do
              {:ok, []} -> {:ok, %{"peers" => %{}}}
              {:ok, _} -> {:error, :unexpected_array_content}
              {:error, reason} -> {:error, reason}
            end

          {:ok, _other} ->
            {:error, :expected_object}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Parse `netclient ping -j` output.

  ## Returns
  - `{:ok, ping_results}` - Map of network_name => [peer_results]
  - `{:ok, %{}}` - No peers found
  - `{:error, reason}` - Parse or ping failure

  ## Examples

      iex> parse_ping_output("{\\"net\\": [{\\"name\\":\\"peer1\\"}]}")
      {:ok, %{"net" => [%{"name" => "peer1"}]}}

      iex> parse_ping_output("\\nNo peers found")
      {:ok, %{}}

      iex> parse_ping_output("\\nFailed to ping peers: connection refused")
      {:error, {:ping_failed, "connection refused"}}
  """
  @spec parse_ping_output(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_ping_output(output) when is_binary(output) do
    cond do
      # Check for "No peers" patterns
      Enum.any?(@no_peers_patterns, &Regex.match?(&1, output)) ->
        {:ok, %{}}

      # Check for "Failed to ping peers" error
      Regex.match?(@ping_error_pattern, output) ->
        # Extract error message after "Failed to ping peers:"
        case Regex.run(~r/Failed to ping peers:\s*(.+)/i, output) do
          [_, error_msg] -> {:error, {:ping_failed, String.trim(error_msg)}}
          _ -> {:error, {:ping_failed, "unknown error"}}
        end

      # Parse JSON output
      true ->
        case extract_and_parse_json(output, :object) do
          {:ok, ping_results} when is_map(ping_results) ->
            # Validate structure: map of network => array of peers
            if valid_ping_structure?(ping_results) do
              {:ok, ping_results}
            else
              {:error, :invalid_ping_structure}
            end

          {:ok, _other} ->
            {:error, :expected_object}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  # Clean netclient logs and extract JSON
  defp extract_and_parse_json(output, expected_type) do
    cleaned = clean_netclient_logs(output)

    case extract_json_by_regex(cleaned, expected_type) do
      {:ok, json_string} ->
        case Jason.decode(json_string) do
          {:ok, data} -> {:ok, data}
          {:error, reason} -> {:error, {:json_parse_error, reason}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Strip [netclient] log lines
  defp clean_netclient_logs(output) do
    output
    |> String.split("\n")
    |> Enum.reject(&String.starts_with?(&1, "[netclient]"))
    |> Enum.join("\n")
  end

  # Extract JSON by scanning for the first balanced bracket/brace structure.
  # Uses a character-by-character scan so it handles arbitrary nesting depth,
  # unlike regex which only handles a fixed number of levels.
  defp extract_json_by_regex(output, type) do
    {open, close, not_found_error} =
      case type do
        :array -> {?[, ?], :no_array_found}
        :object -> {?{, ?}, :no_object_found}
      end

    case find_balanced(output, open, close) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, _} -> {:ok, json}
          {:error, _} -> {:error, :no_valid_json_found}
        end

      :not_found ->
        {:error, not_found_error}
    end
  end

  # Scans `str` for the first occurrence of `open` then finds its matching
  # `close`, correctly handling nested structures and string literals.
  defp find_balanced(str, open, close) do
    chars = String.to_charlist(str)

    case Enum.find_index(chars, &(&1 == open)) do
      nil ->
        :not_found

      start_idx ->
        chars_from_start = Enum.drop(chars, start_idx)

        case scan_balanced(chars_from_start, open, close, 0, []) do
          {:ok, json_chars} -> {:ok, List.to_string(json_chars)}
          :not_found -> :not_found
        end
    end
  end

  # Walk through chars tracking depth, respecting JSON string escaping.
  # Returns {:ok, accumulated_chars} when depth returns to 0 after opening.
  defp scan_balanced([], _open, _close, _depth, _acc), do: :not_found

  defp scan_balanced([h | rest], open, close, depth, acc) do
    cond do
      h == ?" ->
        {string_chars, remaining} = consume_string(rest, [?"])
        scan_balanced(remaining, open, close, depth, acc ++ string_chars)

      h == open ->
        scan_balanced(rest, open, close, depth + 1, acc ++ [h])

      h == close ->
        new_depth = depth - 1
        new_acc = acc ++ [h]

        if new_depth == 0 do
          {:ok, new_acc}
        else
          scan_balanced(rest, open, close, new_depth, new_acc)
        end

      true ->
        scan_balanced(rest, open, close, depth, acc ++ [h])
    end
  end

  # Consume chars until the closing `"`, handling `\"` escapes.
  # Returns {consumed_chars_including_quotes, remaining_chars}.
  defp consume_string([], acc), do: {acc ++ [?"], []}

  defp consume_string([?\\, next | rest], acc) do
    consume_string(rest, acc ++ [?\\, next])
  end

  defp consume_string([?" | rest], acc) do
    {acc ++ [?"], rest}
  end

  defp consume_string([h | rest], acc) do
    consume_string(rest, acc ++ [h])
  end

  # Validate ping result structure: %{network_name => [%{name, address, connected, ...}]}
  defp valid_ping_structure?(results) when is_map(results) do
    Enum.all?(results, fn {_network, peers} ->
      is_list(peers) and
        Enum.all?(peers, fn peer ->
          is_map(peer) and
            Map.has_key?(peer, "name") and
            Map.has_key?(peer, "address") and
            Map.has_key?(peer, "connected")
        end)
    end)
  end

  defp valid_ping_structure?(_), do: false
end
