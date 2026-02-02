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
  - `{:ok, %{"peers" => %{}}}` - No peers found (empty array)
  - `{:error, reason}` - Parse failure

  ## Examples

      iex> parse_peers_output("{\\"interface\\":{\\"name\\":\\"nm-0\\"},\\"peers\\":{\\"net\\":[{\\"public_key\\":\\"..\\"}]}}")
      {:ok, %{"interface" => %{"name" => "nm-0"}, "peers" => %{"net" => [...]}}}

      iex> parse_peers_output("[]")
      {:ok, %{"peers" => %{}}}

      iex> parse_peers_output("\\nNo peers found on interface nm-0")
      {:ok, %{"peers" => %{}}}
  """
  @spec parse_peers_output(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_peers_output(output) when is_binary(output) do
    cond do
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

  # Extract JSON using regex patterns
  defp extract_json_by_regex(output, :array) do
    # Match complete JSON array: [ ... ]
    # This regex finds balanced brackets
    case Regex.run(~r/(\[(?:[^\[\]]|\[(?:[^\[\]]|\[[^\[\]]*\])*\])*\])/s, output) do
      [_, json] ->
        # Validate it's actually valid JSON before returning
        case Jason.decode(json) do
          {:ok, _} -> {:ok, json}
          {:error, _} -> {:error, :no_valid_json_found}
        end

      nil ->
        {:error, :no_array_found}
    end
  end

  defp extract_json_by_regex(output, :object) do
    # Match complete JSON object: { ... }
    # This regex finds balanced braces
    case Regex.run(~r/(\{(?:[^\{\}]|\{(?:[^\{\}]|\{[^\{\}]*\})*\})*\})/s, output) do
      [_, json] ->
        # Validate it's actually valid JSON before returning
        case Jason.decode(json) do
          {:ok, _} -> {:ok, json}
          {:error, _} -> {:error, :no_valid_json_found}
        end

      nil ->
        {:error, :no_object_found}
    end
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
