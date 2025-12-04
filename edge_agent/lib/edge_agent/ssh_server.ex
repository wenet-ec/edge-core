# edge_agent/lib/edge_agent/ssh_server.ex
defmodule EdgeAgent.SshServer do
  @moduledoc """
  SSH server GenServer
  """

  @behaviour :ssh_server_key_api
  @behaviour EdgeAgent.SshServer.Behaviour

  use GenServer

  alias EdgeAgent.SshServer.Authentication
  alias EdgeAgent.SshServer.Config
  alias EdgeAgent.SshServer.HostKeys

  require Logger

  # Client API
  @impl EdgeAgent.SshServer.Behaviour
  def start_server, do: GenServer.call(__MODULE__, :start_server)

  @impl EdgeAgent.SshServer.Behaviour
  def stop_server, do: GenServer.call(__MODULE__, :stop_server)

  @impl EdgeAgent.SshServer.Behaviour
  def server_status, do: GenServer.call(__MODULE__, :server_status)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # GenServer callbacks
  @impl true
  def init(_opts) do
    :ok = File.mkdir_p(Config.ssh_system_dir())
    Logger.info("SSH server initialized on port #{Config.ssh_port()}")

    case do_start_server() do
      {:ok, daemon_ref} ->
        Logger.info("SSH server started successfully on port #{Config.ssh_port()}")
        {:ok, %{daemon_ref: daemon_ref, status: :running}}

      {:error, reason} ->
        Logger.error("Failed to auto-start SSH server: #{inspect(reason)}")
        {:ok, %{daemon_ref: nil, status: :error}}
    end
  end

  @impl true
  def handle_call(:start_server, _from, state) do
    case state.status do
      :running ->
        Logger.info("SSH server already running")
        {:reply, :ok, state}

      _status ->
        case do_start_server() do
          {:ok, daemon_ref} ->
            Logger.info("SSH server started successfully on port #{Config.ssh_port()}")
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
        :ok = :ssh.stop_daemon(state.daemon_ref)
        Logger.info("SSH server stopped successfully")
        {:reply, :ok, %{state | daemon_ref: nil, status: :stopped}}

      _status ->
        Logger.warning("SSH server in unknown state, marking as stopped")
        {:reply, :ok, %{state | daemon_ref: nil, status: :stopped}}
    end
  end

  @impl true
  def handle_call(:server_status, _from, state) do
    {:reply, state.status, state}
  end

  # SSH Server Key API Callbacks (delegates to HostKeys)
  @impl true
  def host_key(algorithm, _daemon_options) do
    HostKeys.host_key(algorithm)
  end

  @impl true
  def is_auth_key(key, user, _daemon_options) do
    Authentication.auth_key?(key, user)
  end

  # Private functions
  defp do_start_server do
    with :ok <- HostKeys.ensure_host_keys() do
      start_ssh_daemon()
    end
  end

  defp start_ssh_daemon do
    password_callback_fun = &Authentication.auth_password/4
    ssh_options = Config.ssh_options(__MODULE__, password_callback_fun)

    Logger.info("Starting SSH daemon on port #{Config.ssh_port()}...")

    case :ssh.daemon(Config.ssh_port(), ssh_options) do
      {:ok, daemon_ref} ->
        Logger.info("SSH daemon started successfully")
        {:ok, daemon_ref}

      {:error, reason} ->
        Logger.error("Failed to start SSH daemon: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
