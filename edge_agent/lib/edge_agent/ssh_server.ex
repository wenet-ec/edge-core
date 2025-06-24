# edge_agent/lib/edge_agent/ssh_server.ex
defmodule EdgeAgent.SshServer do
  @moduledoc """
  SSH server context for EdgeAgent with different algorithm support.

  Supports multiple host key algorithms (RSA, ECDSA, Ed25519) and
  client authentication methods for better security and compatibility.
  """

  use GenServer
  require Logger

  alias EdgeAgent.Settings
  alias EdgeAgent.AdminClient

  @behaviour :ssh_server_key_api

  @ssh_port 22
  @ssh_system_dir "/tmp/ssh_daemon"
  @ssh_user_dir "/tmp"

  # SSH algorithm configuration
  @ssh_algorithms [
    # Key exchange - modern curves first
    kex: [
      :"ecdh-sha2-nistp384",
      :"ecdh-sha2-nistp521",
      :"ecdh-sha2-nistp256",
      :"diffie-hellman-group-exchange-sha256",
      :"diffie-hellman-group16-sha512",
      :"diffie-hellman-group18-sha512",
      :"diffie-hellman-group14-sha256"
    ],
    # Public key algorithms - Ed25519 and ECDSA first, then RSA
    public_key: [
      :"ssh-ed25519",
      :"ecdsa-sha2-nistp384",
      :"ecdsa-sha2-nistp521",
      :"ecdsa-sha2-nistp256",
      :"rsa-sha2-256",
      :"rsa-sha2-512",
      :"ssh-rsa"
    ],
    # Ciphers
    cipher: [
      {:client2server,
       [
         :"aes256-gcm@openssh.com",
         :"aes256-ctr",
         :"aes192-ctr",
         :"aes128-gcm@openssh.com",
         :"aes128-ctr"
       ]},
      {:server2client,
       [
         :"aes256-gcm@openssh.com",
         :"aes256-ctr",
         :"aes192-ctr",
         :"aes128-gcm@openssh.com",
         :"aes128-ctr"
       ]}
    ],
    # MAC algorithms
    mac: [
      {:client2server, [:"hmac-sha2-256", :"hmac-sha2-512"]},
      {:server2client, [:"hmac-sha2-256", :"hmac-sha2-512"]}
    ]
  ]

  @supported_host_key_types [:"ssh-ed25519", :"ecdsa-sha2-nistp256", :"ssh-rsa"]

  # Client API
  def start_server, do: GenServer.call(__MODULE__, :start_server)
  def stop_server, do: GenServer.call(__MODULE__, :stop_server)
  def status, do: GenServer.call(__MODULE__, :status)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("SSH server context initialized")
    :ok = File.mkdir_p(@ssh_system_dir)
    {:ok, %{daemon_ref: nil, status: :stopped}}
  end

  # GenServer callbacks
  @impl true
  def handle_call(:start_server, _from, state) do
    case state.status do
      :running ->
        Logger.info("SSH server already running")
        {:reply, :ok, state}

      _status ->
        case do_start_server() do
          {:ok, daemon_ref} ->
            Logger.info("SSH server started successfully on port #{@ssh_port}")
            {:reply, :ok, %{state | daemon_ref: daemon_ref, status: :running}}

          {:error, reason} = error ->
            Logger.error("Failed to start SSH server: #{inspect(reason)}")
            {:reply, error, %{state | status: :error}}
        end
    end
  end

  @impl true
  def handle_call(:stop_server, _from, state) do
    case state.status do
      :stopped ->
        Logger.info("SSH server already stopped")
        {:reply, :ok, state}

      :running when not is_nil(state.daemon_ref) ->
        case :ssh.stop_daemon(state.daemon_ref) do
          :ok ->
            Logger.info("SSH server stopped successfully")
            {:reply, :ok, %{state | daemon_ref: nil, status: :stopped}}

          {:error, reason} = error ->
            Logger.error("Failed to stop SSH server: #{inspect(reason)}")
            {:reply, error, state}
        end

      _status ->
        Logger.warning("SSH server in unknown state, marking as stopped")
        {:reply, :ok, %{state | daemon_ref: nil, status: :stopped}}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  # SSH Server Key API Callbacks

  @impl true
  def host_key(algorithm, _daemon_options) do
    Logger.debug("Host key requested for algorithm: #{inspect(algorithm)}")

    case algorithm do
      :"ssh-ed25519" ->
        load_or_generate_host_key("ssh_host_ed25519_key", :ed25519)

      # All ECDSA variants use nistp256 key
      alg when alg in [:"ecdsa-sha2-nistp256", :"ecdsa-sha2-nistp384", :"ecdsa-sha2-nistp521"] ->
        load_or_generate_host_key("ssh_host_ecdsa_key", :ecdsa_nistp256)

      # All RSA variants use the same key
      alg when alg in [:"ssh-rsa", :"rsa-sha2-256", :"rsa-sha2-512"] ->
        load_or_generate_host_key("ssh_host_rsa_key", :rsa)

      _ ->
        Logger.debug("Unsupported algorithm requested: #{inspect(algorithm)}")
        {:error, :no_key}
    end
  end

  @impl true
  def is_auth_key(key, user, _daemon_options) do
    Logger.debug("SSH auth attempt for user: #{user}")

    with {:ok, node_id} <- get_node_id(),
         {:ok, ssh_usernames} <- AdminClient.list_ssh_usernames(node_id),
         {:ok, ssh_username} <- find_username(ssh_usernames, to_string(user)),
         {:ok, ssh_public_keys} <- AdminClient.list_ssh_public_keys(ssh_username["id"]),
         true <- validate_public_key(key, ssh_public_keys) do
      Logger.info("SSH authentication successful for user: #{user}")
      true
    else
      {:error, reason} ->
        Logger.warning("SSH authentication failed for user #{user}: #{inspect(reason)}")
        false

      false ->
        Logger.warning("SSH authentication failed for user #{user}: public key not found")
        false
    end
  end

  # Private functions

  defp do_start_server do
    with :ok <- ensure_host_keys(),
         {:ok, daemon_ref} <- start_ssh_daemon() do
      {:ok, daemon_ref}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_host_keys do
    Logger.info("Ensuring host keys are available...")

    # Try to ensure at least one host key exists (preferring Ed25519)
    results =
      Enum.map(@supported_host_key_types, fn algorithm ->
        key_file = algorithm_to_key_file(algorithm)
        key_path = Path.join(@ssh_system_dir, key_file)

        if File.exists?(key_path) do
          Logger.debug("Using existing #{algorithm} host key")
          {:ok, algorithm}
        else
          Logger.info("Generating new #{algorithm} host key")

          case generate_host_key(key_path, algorithm_to_key_type(algorithm)) do
            :ok -> {:ok, algorithm}
            error -> error
          end
        end
      end)

    # Check if at least one key was successful
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

  defp generate_host_key(key_path, key_type) do
    try do
      case key_type do
        :ed25519 ->
          generate_ed25519_key(key_path)

        :ecdsa_nistp256 ->
          generate_ecdsa_key(key_path, "prime256v1")

        :rsa ->
          generate_rsa_key(key_path)
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
        :ok

      {output, exit_code} ->
        Logger.error("OpenSSL Ed25519 generation failed: #{output} (exit code: #{exit_code})")
        {:error, {:openssl_failed, output}}
    end
  end

  defp generate_ecdsa_key(key_path, curve) do
    Logger.info("Generating ECDSA host key using OpenSSL...")

    # Generate key in correct format for Erlang
    case System.cmd("openssl", ["ecparam", "-genkey", "-name", curve, "-noout", "-out", key_path],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        Logger.info("ECDSA host key generated successfully at: #{key_path}")
        :ok

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
        :ok

      {output, exit_code} ->
        Logger.error("OpenSSL RSA generation failed: #{output} (exit code: #{exit_code})")
        {:error, {:openssl_failed, output}}
    end
  end

  defp load_or_generate_host_key(key_file, key_type) do
    key_path = Path.join(@ssh_system_dir, key_file)

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
        :ok -> load_host_key(key_file)
        error -> error
      end
    end
  end

  defp load_host_key(key_name) do
    key_path = Path.join(@ssh_system_dir, key_name)

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

  defp start_ssh_daemon do
    ssh_options = [
      {:ip, :any},
      {:system_dir, String.to_charlist(@ssh_system_dir)},
      {:user_dir, String.to_charlist(@ssh_user_dir)},
      {:key_cb, {__MODULE__, []}},
      {:auth_methods, ~c"publickey"},
      {:preferred_algorithms, @ssh_algorithms},
      {:shell,
       fn user, peer_addr ->
         Logger.info("SSH shell started for user: #{user}, peer: #{inspect(peer_addr)}")
         edge_shell()
       end}
    ]

    Logger.info("Starting SSH daemon on port #{@ssh_port}...")

    case :ssh.daemon(@ssh_port, ssh_options) do
      {:ok, daemon_ref} ->
        Logger.info("SSH daemon started successfully")
        {:ok, daemon_ref}

      {:error, reason} ->
        Logger.error("Failed to start SSH daemon: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp edge_shell do
    spawn(fn ->
      Process.flag(:trap_exit, true)
      IO.puts("Edge Shell - Type 'quit' to exit")
      shell_loop()
    end)
  end

  defp shell_loop do
    case IO.gets("edge> ") do
      :eof ->
        :ok

      {:error, _reason} ->
        shell_loop()

      input ->
        command = input |> to_string() |> String.trim()

        case command do
          "" ->
            shell_loop()

          "quit" ->
            IO.puts("Goodbye!")
            :ok

          "exit" ->
            IO.puts("Goodbye!")
            :ok

          _ ->
            # Execute as hostscript command
            execute_hostscript_command(command)
            shell_loop()
        end
    end
  end

  defp execute_hostscript_command(command) do
    try do
      case System.cmd("/usr/local/bin/hostscript", [command], stderr_to_stdout: true) do
        {output, 0} ->
          IO.puts(output)

        {output, exit_code} ->
          IO.puts(output)
          IO.puts("Command exited with code: #{exit_code}")
      end
    rescue
      error ->
        IO.puts("Error executing command: #{inspect(error)}")
    end
  end

  # Helper functions for algorithm mapping
  defp algorithm_to_key_file(:"ssh-ed25519"), do: "ssh_host_ed25519_key"
  defp algorithm_to_key_file(:"ecdsa-sha2-nistp256"), do: "ssh_host_ecdsa_key"
  defp algorithm_to_key_file(:"ssh-rsa"), do: "ssh_host_rsa_key"

  defp algorithm_to_key_type(:"ssh-ed25519"), do: :ed25519
  defp algorithm_to_key_type(:"ecdsa-sha2-nistp256"), do: :ecdsa_nistp256
  defp algorithm_to_key_type(:"ssh-rsa"), do: :rsa

  # Authentication helper functions
  defp get_node_id do
    case Settings.get("id") do
      nil ->
        Logger.warning("Node ID not found in settings")
        {:error, :node_id_not_found}

      node_id ->
        {:ok, node_id}
    end
  end

  defp find_username(ssh_usernames, username) do
    case Enum.find(ssh_usernames, fn u -> u["username"] == username end) do
      nil ->
        Logger.debug("Username '#{username}' not found in SSH usernames")
        {:error, :username_not_found}

      ssh_username ->
        Logger.debug("Found SSH username: #{ssh_username["id"]}")
        {:ok, ssh_username}
    end
  end

  defp validate_public_key(provided_key, ssh_public_keys) do
    Logger.debug("Raw provided key format: #{inspect(provided_key, limit: :infinity)}")

    provided_key_string = format_public_key(provided_key)
    # Normalize: extract just algorithm + key data (remove comment if present)
    provided_key_normalized = normalize_ssh_key(provided_key_string)

    Logger.debug("Formatted provided key: #{provided_key_string}")
    Logger.debug("Normalized provided key: #{provided_key_normalized}")
    Logger.debug("Against #{length(ssh_public_keys)} stored keys")

    Enum.each(ssh_public_keys, fn stored_key ->
      Logger.debug("Stored key: #{stored_key["public_key"]}")
    end)

    result =
      Enum.any?(ssh_public_keys, fn stored_key ->
        stored_key_string = String.trim(stored_key["public_key"])
        # Normalize stored key too (remove comment)
        stored_key_normalized = normalize_ssh_key(stored_key_string)

        match = provided_key_normalized == stored_key_normalized

        if match do
          Logger.debug("Key match found for key: #{stored_key["key_name"]}")
        else
          Logger.debug("Key mismatch - provided: #{provided_key_normalized}")
          Logger.debug("Key mismatch - stored: #{stored_key_normalized}")
        end

        match
      end)

    unless result do
      Logger.debug("No matching public key found")
    end

    result
  end

  # New function to normalize SSH keys for comparison
  defp normalize_ssh_key(key_string) do
    # Split into parts: algorithm, key_data, comment (optional)
    case String.split(key_string, " ", parts: 3) do
      [algorithm, key_data, _comment] ->
        "#{algorithm} #{key_data}"

      [algorithm, key_data] ->
        "#{algorithm} #{key_data}"

      _ ->
        key_string
    end
  end

  defp format_public_key({key_type, key_data, _comment})
       when is_list(key_type) and is_binary(key_data) do
    # Convert erlang SSH key format to string format
    key_type_string =
      case key_type do
        ~c"ssh-rsa" -> "ssh-rsa"
        ~c"ssh-dss" -> "ssh-dss"
        ~c"ecdsa-sha2-nistp256" -> "ecdsa-sha2-nistp256"
        ~c"ecdsa-sha2-nistp384" -> "ecdsa-sha2-nistp384"
        ~c"ecdsa-sha2-nistp521" -> "ecdsa-sha2-nistp521"
        ~c"ssh-ed25519" -> "ssh-ed25519"
        other when is_list(other) -> List.to_string(other)
        other -> to_string(other)
      end

    key_data_base64 = Base.encode64(key_data)
    "#{key_type_string} #{key_data_base64}"
  end

  defp format_public_key({{:ECPoint, point_data}, {:namedCurve, {1, 3, 101, 112}}}) do
    # Ed25519 curve point - need to reconstruct the proper SSH format
    ssh_ed25519_prefix = "ssh-ed25519"

    # For Ed25519, SSH format is: string "ssh-ed25519" + string key_data
    # We need to encode it properly for SSH wire format
    algorithm_length = byte_size(ssh_ed25519_prefix)
    key_length = byte_size(point_data)

    ssh_wire_format =
      <<algorithm_length::32>> <> ssh_ed25519_prefix <> <<key_length::32>> <> point_data

    key_data_base64 = Base.encode64(ssh_wire_format)
    "ssh-ed25519 #{key_data_base64}"
  end

  # Handle the case where Ed25519 key comes in as raw binary
  defp format_public_key({:"ssh-ed25519", key_data}) when is_binary(key_data) do
    key_data_base64 = Base.encode64(key_data)
    "ssh-ed25519 #{key_data_base64}"
  end

  defp format_public_key(key) when is_binary(key) do
    String.trim(key)
  end

  defp format_public_key(other) do
    Logger.warning("Unknown public key format: #{inspect(other)}")
    Logger.debug("Key format details: #{inspect(other, limit: :infinity)}")
    ""
  end
end
