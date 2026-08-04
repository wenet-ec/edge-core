# edge_admin/lib/edge_admin/random.ex
defmodule EdgeAdmin.Random do
  @moduledoc """
  Shared cryptographically secure random-value helpers.

  The output formats are intentionally explicit: opaque credentials use
  unpadded Base64, while readable identifiers use lowercase Base32.
  """

  @doc """
  Generates a 32-byte cryptographically secure value as unpadded Base64.
  """
  @spec token() :: String.t()
  def token do
    32 |> :crypto.strong_rand_bytes() |> Base.encode64(padding: false)
  end

  @doc """
  Generates a lowercase Base32 string with the requested length.
  """
  @spec string(pos_integer()) :: String.t()
  def string(length) when is_integer(length) and length > 0 do
    byte_count = ceil(length * 5 / 8)

    byte_count
    |> :crypto.strong_rand_bytes()
    |> Base.encode32(case: :lower, padding: false)
    |> String.slice(0..(length - 1))
  end
end
