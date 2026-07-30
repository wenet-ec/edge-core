# edge_admin/lib/edge_admin/password_hasher.ex
defmodule EdgeAdmin.PasswordHasher do
  @moduledoc """
  Algorithm-agile password hashing.

  The internal `:password_hashers` list in `config/config.exs` is ordered. Its
  first algorithm writes new hashes. Every listed algorithm can verify its own
  self-identifying stored hashes; a valid match from a non-first algorithm is
  `:legacy` and should be rehashed by the caller.

  Rotating algorithms is an intentional code change: add the successor at the
  front of `@hashers`, release it everywhere, then remove the retired hasher
  only after every remaining hash has been migrated or reset.
  """

  alias EdgeAdmin.PasswordHashers.Argon2

  @hashers Application.compile_env(:edge_admin, :password_hashers, [Argon2])

  @type hasher :: module()
  @type verification :: :current | :legacy

  @callback matches?(String.t()) :: boolean()
  @callback hash(String.t()) :: String.t()
  @callback verify(String.t(), String.t()) :: boolean()

  @doc "Hashes a password with the highest-priority internal algorithm."
  @spec hash(String.t()) :: String.t()
  def hash(password) when is_binary(password), do: hash_with(password, @hashers)

  @doc "Verifies a password against its self-identifying stored hash."
  @spec verify(String.t(), String.t()) :: {:ok, verification()} | :error
  def verify(password, stored_hash), do: verify_with(password, stored_hash, @hashers)

  @doc false
  @spec hash_with(String.t(), [hasher()]) :: String.t()
  def hash_with(password, [hasher | _rest]) when is_binary(password), do: hasher.hash(password)

  @doc false
  @spec verify_with(String.t(), String.t(), [hasher()]) :: {:ok, verification()} | :error
  def verify_with(password, stored_hash, [current | legacy_hashers])
      when is_binary(password) and is_binary(stored_hash) do
    cond do
      current.matches?(stored_hash) and current.verify(password, stored_hash) ->
        {:ok, :current}

      hasher = Enum.find(legacy_hashers, & &1.matches?(stored_hash)) ->
        if hasher.verify(password, stored_hash), do: {:ok, :legacy}, else: :error

      true ->
        :error
    end
  end

  def verify_with(_password, _stored_hash, _hashers), do: :error
end
