# edge_admin/lib/edge_admin/ssh/validators/ssh_public_key_validators.ex
defmodule EdgeAdmin.Ssh.Validators.SshPublicKeyValidators do
  @moduledoc "Pure validators for SSH public-key names and key material."

  alias EdgeAdmin.Naming

  @supported_algorithms Naming.ssh_public_key_algorithms()
  @ssh_key_regex Naming.ssh_public_key_regex()

  @spec supported_algorithms() :: [String.t()]
  def supported_algorithms, do: @supported_algorithms

  @spec key_name_error(term()) :: :ok | {:error, String.t()}
  def key_name_error(name) when is_binary(name) do
    cond do
      byte_size(name) < 1 -> {:error, "should be at least 1 character(s)"}
      byte_size(name) > 255 -> {:error, "should be at most 255 character(s)"}
      true -> :ok
    end
  end

  def key_name_error(_name), do: {:error, "has invalid format"}

  @doc "Validates key format, supported algorithm, and base64 key data."
  @spec validate_key_format(term()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_key_format(public_key) when is_binary(public_key) do
    trimmed_key = String.trim(public_key)

    with true <- Regex.match?(@ssh_key_regex, trimmed_key),
         {:ok, algorithm} <- extract_algorithm(trimmed_key),
         :ok <- validate_algorithm(algorithm),
         {:ok, key_data} <- extract_key_data(trimmed_key),
         {:ok, _decoded} <- Base.decode64(key_data, ignore: :whitespace) do
      {:ok, algorithm}
    else
      false -> {:error, "invalid SSH key format"}
      {:error, reason} -> {:error, reason}
      :error -> {:error, "invalid base64 key data"}
    end
  end

  def validate_key_format(_public_key), do: {:error, "invalid SSH key format"}

  defp validate_algorithm(algorithm) when algorithm in @supported_algorithms, do: :ok

  defp validate_algorithm(algorithm),
    do: {:error, "unsupported key algorithm '#{algorithm}'. Supported: #{Enum.join(@supported_algorithms, ", ")}"}

  defp extract_algorithm(public_key) do
    case Regex.run(@ssh_key_regex, String.trim(public_key)) do
      [_full, algorithm, _key_data, _comment] -> {:ok, algorithm}
      [_full, algorithm, _key_data] -> {:ok, algorithm}
      _ -> {:error, "invalid SSH key format"}
    end
  end

  defp extract_key_data(public_key) do
    case Regex.run(@ssh_key_regex, String.trim(public_key)) do
      [_full, _algorithm, key_data, _comment] -> {:ok, key_data}
      [_full, _algorithm, key_data] -> {:ok, key_data}
      _ -> {:error, "invalid SSH key format"}
    end
  end
end
