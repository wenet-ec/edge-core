defmodule Nexmaker.Api.EnrollmentKeys do
  @moduledoc """
  Enrollment key management for Netmaker API.

  Enrollment keys are used to join hosts to networks. Each key can have
  usage limits and expiration times.

  ## Examples

      # Create an enrollment key
      {:ok, key} = Nexmaker.Api.EnrollmentKeys.create("admin-cluster",
        uses_remaining: 10,
        expiration: 86400  # 24 hours in seconds
      )

      # List all keys for a network
      {:ok, keys} = Nexmaker.Api.EnrollmentKeys.list("admin-cluster")

      # Delete a key
      {:ok, _} = Nexmaker.Api.EnrollmentKeys.delete("admin-cluster", "key-id")
  """

  alias Nexmaker.Api

  @doc """
  Lists all enrollment keys.

  ## Parameters
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, keys}` - List of enrollment key maps (each key has `networks` field)
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, keys} = Nexmaker.Api.EnrollmentKeys.list()

      # Filter by network if needed
      admin_keys = Enum.filter(keys, fn key ->
        "admin-cluster" in key["networks"]
      end)
  """
  @spec list(keyword()) :: {:ok, [map()]} | {:error, any()}
  def list(opts \\ []) do
    Api.request(:get, "/api/v1/enrollment-keys", opts)
  end

  @doc """
  Creates an enrollment key for a network.

  ## Parameters
    - network_name: String - Network name
    - attrs: Map - Key attributes (optional):
      - `:uses_remaining` - Number of allowed uses (default: unlimited)
      - `:expiration` - Expiration time in seconds from now (default: no expiration)
      - `:tags` - List of tags for the key (each tag must be 3-32 chars). Defaults to ["default"]
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, key}` - Created enrollment key map (includes `value` field with token)
    - `{:error, reason}` - Error occurred

  ## Examples

      # Create one-time use key
      {:ok, key} = Nexmaker.Api.EnrollmentKeys.create("cluster-abc", %{
        uses_remaining: 1,
        tags: ["agent"]
      })

      # Create key with 24-hour expiration
      {:ok, key} = Nexmaker.Api.EnrollmentKeys.create("admin-cluster", %{
        expiration: 86400,
        tags: ["admin", "bootstrap"]
      })
  """
  @spec create(String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def create(network_name, attrs \\ %{}, opts \\ []) do
    # Tags are required by the API - default to ["default"] if not provided.
    # uses_remaining defaults to 1 — Netmaker rejects keys with uses_remaining: 0
    # and no expiration set.
    body =
      attrs
      |> Map.put(:networks, [network_name])
      |> Map.put_new(:tags, ["default"])
      |> Map.put_new(:uses_remaining, 1)

    Api.request(:post, "/api/v1/enrollment-keys", Keyword.put(opts, :body, body))
  end

  @doc """
  Updates an enrollment key.

  ## Parameters
    - key_id: String - Enrollment key ID
    - attrs: Map - Attributes to update
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, key}` - Updated enrollment key map
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, key} = Nexmaker.Api.EnrollmentKeys.update("key-id", %{
        uses_remaining: 5
      })
  """
  @spec update(String.t(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def update(key_id, attrs, opts \\ []) do
    Api.request(
      :put,
      "/api/v1/enrollment-keys/#{key_id}",
      Keyword.put(opts, :body, attrs)
    )
  end

  @doc """
  Deletes an enrollment key.

  ## Parameters
    - key_id: String - Enrollment key ID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Key deleted
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.EnrollmentKeys.delete("key-id")
  """
  @spec delete(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete(key_id, opts \\ []) do
    Api.request(:delete, "/api/v1/enrollment-keys/#{key_id}", opts)
  end
end
