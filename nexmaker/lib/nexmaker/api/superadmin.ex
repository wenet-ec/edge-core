defmodule Nexmaker.Api.Superadmin do
  @moduledoc """
  Superadmin management for Netmaker API.

  Netmaker has a superadmin user for web UI access. This is optional -
  Edge Admin doesn't need it, as it uses MASTER_KEY directly.

  ## Use Cases

  - Creating initial superadmin for web UI access
  - Checking if superadmin exists
  - Transferring superadmin role (admin operations)

  ## Examples

      # Check if superadmin exists
      {:ok, %{"issuperadmin" => true}} = Nexmaker.Api.Superadmin.check()

      # Create superadmin (only works if none exists)
      {:ok, user} = Nexmaker.Api.Superadmin.create(%{
        username: "admin",
        password: "secure-password"
      })
  """

  alias Nexmaker.Api

  @doc """
  Checks if a superadmin exists.

  ## Options
    - `:base_url` - Netmaker API base URL
    - `:master_key` - Netmaker master key (not required for this endpoint)

  ## Returns
    - `{:ok, boolean}` - True if superadmin exists, false otherwise
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, true} = Nexmaker.Api.Superadmin.check()
      {:ok, false} = Nexmaker.Api.Superadmin.check()
  """
  @spec check(keyword()) :: {:ok, boolean()} | {:error, any()}
  def check(opts \\ []) do
    # This endpoint doesn't require authentication
    base_url = Keyword.get(opts, :base_url) || Application.get_env(:nexmaker, :base_url)

    unless base_url do
      raise ArgumentError, "base_url is required for Superadmin.check/1"
    end

    url = "#{String.trim_trailing(base_url, "/")}/api/users/adm/hassuperadmin"

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        # The API returns a boolean directly (true or false)
        case Jason.decode(body) do
          {:ok, result} when is_boolean(result) ->
            {:ok, result}

          {:ok, %{"issuperadmin" => is_super}} when is_boolean(is_super) ->
            # Support map format if API changes
            {:ok, is_super}

          {:ok, other} ->
            {:error, {:unexpected_response, other}}

          {:error, reason} ->
            {:error, {:json_decode_error, reason}}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        {:error, {:http_error, status, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:http_client_error, reason}}
    end
  end

  @doc """
  Creates a superadmin user.

  This endpoint only works if no superadmin exists yet.
  It does not require authentication (bootstrap endpoint).

  ## Parameters
    - attrs: Map - Superadmin attributes:
      - `:username` - Admin username
      - `:password` - Admin password
    - opts: Keyword - API options (base_url only, no master_key needed)

  ## Returns
    - `{:ok, user}` - Created superadmin user map
    - `{:error, reason}` - Error occurred (e.g., superadmin already exists)

  ## Examples

      {:ok, user} = Nexmaker.Api.Superadmin.create(%{
        username: "admin",
        password: "secure-password-123"
      })
  """
  @spec create(map(), keyword()) :: {:ok, map()} | {:error, any()}
  def create(attrs, opts \\ []) do
    # This endpoint doesn't require authentication (bootstrap)
    base_url = Keyword.get(opts, :base_url) || Application.get_env(:nexmaker, :base_url)

    unless base_url do
      raise ArgumentError, "base_url is required for Superadmin.create/2"
    end

    url = "#{String.trim_trailing(base_url, "/")}/api/users/adm/createsuperadmin"
    headers = [{"Content-Type", "application/json"}]
    body = Jason.encode!(attrs)

    case HTTPoison.post(url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: status, body: response_body}}
      when status in 200..299 ->
        Jason.decode(response_body)

      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
        {:error, {:http_error, status, response_body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:http_client_error, reason}}
    end
  end

  @doc """
  Transfers superadmin role to another user.

  ## Parameters
    - username: String - Username to transfer superadmin role to
    - opts: Keyword - API options (base_url, master_key)

  ## Returns
    - `{:ok, response}` - Superadmin role transferred
    - `{:error, reason}` - Error occurred

  ## Examples

      {:ok, _} = Nexmaker.Api.Superadmin.transfer("new-admin")
  """
  @spec transfer(String.t(), keyword()) :: {:ok, any()} | {:error, any()}
  def transfer(username, opts \\ []) do
    Api.request(:post, "/api/users/adm/transfersuperadmin/#{username}", opts)
  end
end
