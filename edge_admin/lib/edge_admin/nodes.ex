# edge_admin/lib/edge_admin/nodes.ex
defmodule EdgeAdmin.Nodes do
  @moduledoc """
  The Nodes context.
  """

  import Ecto.Query, warn: false
  alias EdgeAdmin.Repo

  alias EdgeAdmin.Nodes.Node

  alias EdgeAdmin.VPN.HeadscaleClient
  require Logger

  @doc """
  Returns the list of nodes.

  ## Examples

      iex> list_nodes()
      [%Node{}, ...]

  """
  def list_nodes do
    Repo.all(Node)
    |> Enum.map(&Node.populate_virtual_fields/1)
  end

  @doc """
  Gets a single node.

  Raises `Ecto.NoResultsError` if the Node does not exist.

  ## Examples

      iex> get_node!(123)
      %Node{}

      iex> get_node!(456)
      ** (Ecto.NoResultsError)

  """
  def get_node!(id) do
    Repo.get!(Node, id)
    |> Node.populate_virtual_fields()
  end

  @doc """
  Creates a node.

  ## Examples

      iex> create_node(%{field: value})
      {:ok, %Node{}}

      iex> create_node(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_node(attrs \\ %{}) do
    %Node{}
    |> Node.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, node} -> {:ok, Node.populate_virtual_fields(node)}
      error -> error
    end
  end

  @doc """
  Updates a node.

  ## Examples

      iex> update_node(node, %{field: new_value})
      {:ok, %Node{}}

      iex> update_node(node, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_node(%Node{} = node, attrs) do
    node
    |> Node.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, node} -> {:ok, Node.populate_virtual_fields(node)}
      error -> error
    end
  end

  @doc """
  Deletes a node.

  ## Examples

      iex> delete_node(node)
      {:ok, %Node{}}

      iex> delete_node(node)
      {:error, %Ecto.Changeset{}}

  """
  def delete_node(%Node{} = node) do
    Repo.delete(node)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking node changes.

  ## Examples

      iex> change_node(node)
      %Ecto.Changeset{data: %Node{}}

  """
  def change_node(%Node{} = node, attrs \\ %{}) do
    Node.changeset(node, attrs)
  end

  def fetch_vpn_info(%Node{} = node) do
    vpn_hostname = Node.vpn_hostname(node)

    case HeadscaleClient.get_node_by_hostname(vpn_hostname) do
      {:ok, vpn_info} ->
        # Update node with VPN info
        update_node(node, vpn_info)

      {:error, reason} ->
        Logger.warning("Failed to get VPN info for #{vpn_hostname}: #{inspect(reason)}")
        # Return node unchanged if VPN lookup fails
        {:ok, node}
    end
  end

  def create_node_with_vpn_info(attrs \\ %{}) do
    with {:ok, node} <- create_node(attrs),
         {:ok, node_with_vpn_info} <- fetch_vpn_info(node) do
      {:ok, node_with_vpn_info}
    else
      error -> error
    end
  end

  def get_node_with_vpn_info!(id) do
    node = get_node!(id)

    case fetch_vpn_info(node) do
      {:ok, node_with_vpn_info} -> node_with_vpn_info
      {:error, _reason} -> node
    end
  end
end
