# edge_agent/lib/edge_agent/ssh_server/host_key_manager.ex
defmodule EdgeAgent.SshServer.HostKeyManager do
  @moduledoc """
  Manages SSH host keys - generation, loading, and validation.
  """

  require Logger
  alias EdgeAgent.SshServer.Config

  @type key_type :: :ed25519 | :ecdsa_nistp256 | :rsa
  @type algorithm :: atom()

  def ensure_host_keys do
    Logger.info("Ensuring host keys are available...")

    results =
      Enum.map(Config.supported_host_key_types(), fn algorithm ->
        key_file = algorithm_to_key_file(algorithm)
        key_path = Path.join(Config.ssh_system_dir(), key_file)

        if File.exists?(key_path) do
          Logger.debug("Using existing #{algorithm} host key")
          {:ok, algorithm}
        else
          Logger.info("Generating new #{algorithm} host key")
          generate_host_key(key_path, algorithm_to_key_type(algorithm))
        end
      end)

    case Enum.find(results, fn
           {:ok, _} -> true
           _ -> false
         end) do
      nil ->
        Logger.error("Failed to ensure any host keys")
        {:error, :no_host_keys}

      _ ->
        Logger.info("Host keys ready")
        :ok
    end
  end

  def host_key(algorithm) do
    Logger.debug("Host key requested for algorithm: #{inspect(algorithm)}")

    case algorithm do
      :"ssh-ed25519" ->
        load_or_generate_host_key("ssh_host_ed25519_key", :ed25519)

      alg when alg in [:"ecdsa-sha2-nistp256", :"ecdsa-sha2-nistp384", :"ecdsa-sha2-nistp521"] ->
        load_or_generate_host_key("ssh_host_ecdsa_key", :ecdsa_nistp256)

      alg when alg in [:"ssh-rsa", :"rsa-sha2-256", :"rsa-sha2-512"] ->
        load_or_generate_host_key("ssh_host_rsa_key", :rsa)

      _ ->
        Logger.debug("Unsupported algorithm requested: #{inspect(algorithm)}")
        {:error, :no_key}
    end
  end

  # Private functions

  defp generate_host_key(key_path, key_type) do
    try do
      case key_type do
        :ed25519 -> generate_ed25519_key(key_path)
        :ecdsa_nistp256 -> generate_ecdsa_key(key_path, "prime256v1")
        :rsa -> generate_rsa_key(key_path)
      end
    rescue
      error ->
        Logger.error("Failed to generate #{key_type} host key: #{inspect(error)}")
        {:error, {:key_generation_failed, error}}
    end
  end

  defp generate_ed25519_key(key_path) do
    Logger.info("Generating Ed25519 host key using OpenSSL...")

    case System.cmd("openssl", ["genpkey", "-algorithm", "Ed25519", "-out", key_path],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        Logger.info("Ed25519 host key generated successfully at: #{key_path}")
        {:ok, :ed25519}

      {output, exit_code} ->
        Logger.error("OpenSSL Ed25519 generation failed: #{output} (exit code: #{exit_code})")
        {:error, {:openssl_failed, output}}
    end
  end

  defp generate_ecdsa_key(key_path, curve) do
    Logger.info("Generating ECDSA host key using OpenSSL...")

    case System.cmd("openssl", ["ecparam", "-genkey", "-name", curve, "-noout", "-out", key_path],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        Logger.info("ECDSA host key generated successfully at: #{key_path}")
        {:ok, :ecdsa_nistp256}

      {output, exit_code} ->
        Logger.error("OpenSSL ECDSA generation failed: #{output} (exit code: #{exit_code})")
        {:error, {:openssl_failed, output}}
    end
  end

  defp generate_rsa_key(key_path) do
    Logger.info("Generating RSA host key using OpenSSL...")

    case System.cmd("openssl", ["genrsa", "-out", key_path, "2048"], stderr_to_stdout: true) do
      {_output, 0} ->
        Logger.info("RSA host key generated successfully at: #{key_path}")
        {:ok, :rsa}

      {output, exit_code} ->
        Logger.error("OpenSSL RSA generation failed: #{output} (exit code: #{exit_code})")
        {:error, {:openssl_failed, output}}
    end
  end

  defp load_or_generate_host_key(key_file, key_type) do
    key_path = Path.join(Config.ssh_system_dir(), key_file)

    if File.exists?(key_path) do
      case load_host_key(key_file) do
        {:ok, key} ->
          Logger.debug("Successfully loaded #{key_type} host key")
          {:ok, key}

        error ->
          Logger.error("Failed to load #{key_type} host key: #{inspect(error)}")
          error
      end
    else
      Logger.info("#{key_type} host key not found, generating...")

      case generate_host_key(key_path, key_type) do
        {:ok, _} -> load_host_key(key_file)
        error -> error
      end
    end
  end

  defp load_host_key(key_name) do
    key_path = Path.join(Config.ssh_system_dir(), key_name)

    case File.read(key_path) do
      {:ok, pem_data} ->
        try do
          [pem_entry] = :public_key.pem_decode(pem_data)
          private_key = :public_key.pem_entry_decode(pem_entry)
          {:ok, private_key}
        rescue
          error ->
            Logger.error("Failed to decode PEM key: #{inspect(error)}")
            {:error, :invalid_key_format}
        end

      {:error, reason} ->
        Logger.debug("Could not read key file #{key_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp algorithm_to_key_file(:"ssh-ed25519"), do: "ssh_host_ed25519_key"
  defp algorithm_to_key_file(:"ecdsa-sha2-nistp256"), do: "ssh_host_ecdsa_key"
  defp algorithm_to_key_file(:"ssh-rsa"), do: "ssh_host_rsa_key"

  defp algorithm_to_key_type(:"ssh-ed25519"), do: :ed25519
  defp algorithm_to_key_type(:"ecdsa-sha2-nistp256"), do: :ecdsa_nistp256
  defp algorithm_to_key_type(:"ssh-rsa"), do: :rsa
end
