# nexmaker/lib/nexmaker/api/enrollment_keys.ex
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
    # Note: tags must be unique across ALL existing enrollment keys (not just within this
    # network). Duplicate tag → 400 bad request.
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
    - `{:ok, %{body: ""}}` - Key deleted (empty body on success)
    - `{:error, {:bad_request, body}}` - Key not found (Netmaker uses 400, not 404)
    - `{:error, reason}` - Other error

  ## Notes

  Netmaker returns HTTP 400 (`FormatError(err, "badrequest")`) when the key is not found —
  not 404 or 500. After `Nexmaker.Api.normalize/1` this becomes `{:error, {:bad_request, body}}`,
  not `{:error, :not_found}`. Callers wanting to treat a missing key as success must match on
  `{:error, {:bad_request, _}}` explicitly.

  ## Examples

      {:ok, _} = Nexmaker.Api.EnrollmentKeys.delete("key-id")
  """
  @spec delete(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def delete(key_id, opts \\ []) do
    Api.request(:delete, "/api/v1/enrollment-keys/#{key_id}", opts)
  end

  @doc """
  Gets the default enrollment key for a network.

  Each network has at most one key tagged "default". Returns that key with its
  current token value populated.

  ## Parameters
    - network_name: String - Network name
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, key}` - Enrollment key map (includes `value` token field)
    - `{:error, {:bad_request, body}}` - Network not found or no default key exists
    - `{:error, reason}` - Other error
  """
  @spec get_default_for_network(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def get_default_for_network(network_name, opts \\ []) do
    Api.request(:get, "/api/v1/enrollment-keys/network/#{network_name}/default", opts)
  end

  @doc """
  Regenerates the token for an existing enrollment key.

  The key ID stays the same; only the `value` (join token) changes. Useful when
  a token has been exposed and needs to be rotated without changing key settings.

  ## Parameters
    - key_id: String - Enrollment key ID
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, key}` - Updated enrollment key map with new `value` token
    - `{:error, {:bad_request, body}}` - Key not found
    - `{:error, reason}` - Other error
  """
  @spec regenerate_token(String.t(), keyword()) :: {:ok, map()} | {:error, any()}
  def regenerate_token(key_id, opts \\ []) do
    Api.request(:post, "/api/v1/enrollment-keys/#{key_id}/regenerate-token", opts)
  end
end
