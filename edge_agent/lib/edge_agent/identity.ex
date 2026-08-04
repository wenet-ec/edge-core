# edge_agent/lib/edge_agent/identity.ex
defmodule EdgeAgent.Identity do
  @moduledoc """
  Determines and persists the Agent node identity.
  """

  alias EdgeAgent.Settings

  require Logger

  @type identity :: %{
          node_id: String.t(),
          recovery_key: String.t() | nil
        }

  @spec determine() :: {:ok, identity()} | {:error, :invalid_persisted_node_id | :invalid_recovery_key | term()}
  def determine do
    persisted_node_id = Settings.get_node_id()
    recovery_key = Application.get_env(:edge_agent, :recovery_key)

    case select_node_identity(persisted_node_id, recovery_key) do
      {:ok, {:persisted, node_id, nil}} ->
        Logger.info("Loaded node installation ID: #{String.slice(node_id, 0, 8)}...")
        {:ok, %{node_id: node_id, recovery_key: nil}}

      {:ok, {:recovery, node_id, recovery_key}} ->
        with {:ok, node_id} <- persist_node_id(node_id, "Recovered") do
          {:ok, %{node_id: node_id, recovery_key: recovery_key}}
        end

      :generate ->
        node_id = Uniq.UUID.uuid7()

        with {:ok, node_id} <- persist_node_id(node_id, "Generated") do
          {:ok, %{node_id: node_id, recovery_key: nil}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Selects the node identity source for bootstrap.

  A persisted node ID wins. Otherwise a valid recovery key supplies the node
  ID and cluster, and when neither exists the caller should generate a new ID.
  """
  @spec select_node_identity(String.t() | nil, String.t() | nil) ::
          {:ok, {:persisted | :recovery, String.t(), String.t() | nil}}
          | :generate
          | {:error, :invalid_persisted_node_id | :invalid_recovery_key}
  def select_node_identity(persisted_node_id, recovery_key) do
    case persisted_node_id do
      node_id when is_binary(node_id) and byte_size(node_id) > 0 ->
        case validate_node_id(node_id) do
          {:ok, uuid} -> {:ok, {:persisted, uuid, nil}}
          :error -> {:error, :invalid_persisted_node_id}
        end

      nil ->
        select_recovery_key(recovery_key)

      "" ->
        select_recovery_key(recovery_key)

      _ ->
        {:error, :invalid_persisted_node_id}
    end
  end

  defp select_recovery_key(recovery_key) when is_binary(recovery_key) and byte_size(recovery_key) > 0 do
    with {:ok, decoded} <- Base.decode64(recovery_key),
         {:ok, %{"node_id" => node_id, "nonce" => nonce, "cluster_name" => cluster_name}} <- JSON.decode(decoded),
         true <- is_binary(nonce) and nonce != "",
         true <- is_binary(cluster_name) and cluster_name != "",
         {:ok, node_id} <- validate_node_id(node_id) do
      {:ok, {:recovery, node_id, recovery_key}}
    else
      _ -> {:error, :invalid_recovery_key}
    end
  end

  defp select_recovery_key(nil), do: :generate
  defp select_recovery_key(""), do: :generate
  defp select_recovery_key(_recovery_key), do: {:error, :invalid_recovery_key}

  defp validate_node_id(node_id) do
    case Ecto.UUID.cast(node_id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> :error
    end
  end

  defp persist_node_id(node_id, action) do
    case Settings.set_node_id(node_id) do
      {:ok, _setting} ->
        Logger.info("#{action} node installation ID: #{String.slice(node_id, 0, 8)}...")
        {:ok, node_id}

      {:error, reason} ->
        {:error, {:node_id_persistence_failed, reason}}
    end
  end
end
