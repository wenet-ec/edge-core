# edge_admin/lib/edge_admin/password_hashers/algorithms/argon2.ex
defmodule EdgeAdmin.PasswordHashers.Algorithms.Argon2 do
  @moduledoc false
  @behaviour EdgeAdmin.PasswordHashers

  @impl true
  def matches?("$argon2" <> _rest), do: true
  def matches?(_stored_hash), do: false

  @impl true
  def hash(password), do: Elixir.Argon2.hash_pwd_salt(password)

  @impl true
  def verify(password, stored_hash), do: Elixir.Argon2.verify_pass(password, stored_hash)
end
