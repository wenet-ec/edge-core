# edge_admin/lib/edge_admin/config.ex
defmodule EdgeAdmin.Config do
  @moduledoc """
  This modules provides various helpers to handle environment variables
  """

  @type value_type :: :string | :integer | :boolean | :uri | :cors | :list | :atom | :positive_integer
  @type config_type :: String.t() | integer() | boolean() | URI.t() | [String.t()] | atom()

  @spec get_env(String.t(), nil | value_type(), any()) :: config_type()
  def get_env(key, type \\ :string, default \\ nil) do
    value = System.get_env(key)

    case value do
      nil -> default
      _ -> parse_env(value, type)
    end
  end

  @spec get_env!(String.t(), nil | value_type()) :: config_type()
  def get_env!(key, type \\ :string) do
    value = System.fetch_env!(key)

    parse_env(value, type)
  end

  defp parse_env(value, :string), do: value
  defp parse_env(value, :integer), do: String.to_integer(value)

  defp parse_env(nil, :boolean), do: false
  defp parse_env("", :boolean), do: false
  defp parse_env(value, :boolean), do: String.downcase(value) in ~w(true 1)

  defp parse_env(nil, :cors), do: nil

  defp parse_env(value, :cors) when is_bitstring(value) do
    case String.split(value, ",") do
      [origin] -> origin
      origins -> origins
    end
  end

  defp parse_env(nil, :uri), do: nil
  defp parse_env("", :uri), do: nil
  defp parse_env(value, :uri), do: URI.parse(value)

  defp parse_env(nil, :list), do: []
  defp parse_env("", :list), do: []

  defp parse_env(value, :list) when is_bitstring(value) do
    String.split(value, ",") |> Enum.map(&String.trim/1)
  end

  defp parse_env(value, :atom) when is_bitstring(value) do
    String.to_atom(value)
  end

  defp parse_env(value, :positive_integer) do
    int = String.to_integer(value)

    if int <= 0 do
      raise ArgumentError, "expected positive integer, got: #{int}"
    end

    int
  end

  @spec build_admin_cluster_name(String.t()) :: String.t()
  def build_admin_cluster_name(suffix) do
    prefix = "admin-cluster-"
    max_total_length = 32

    # Validate format: lowercase alphanumeric with hyphens, no leading/trailing hyphens
    unless Regex.match?(~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/, suffix) do
      raise ArgumentError, """
      ADMIN_CLUSTER_NAME must match format: lowercase alphanumeric with hyphens, no leading/trailing hyphens
      Got: #{suffix}
      """
    end

    # Build full name
    full_name = "#{prefix}#{suffix}"

    # Validate length
    if String.length(full_name) > max_total_length do
      max_suffix_length = max_total_length - String.length(prefix)

      raise ArgumentError, """
      ADMIN_CLUSTER_NAME exceeds Netmaker's #{max_total_length} character limit
      Prefix: #{prefix} (#{String.length(prefix)} chars)
      Suffix: #{suffix} (#{String.length(suffix)} chars)
      Total: #{String.length(full_name)} chars
      Max suffix length: #{max_suffix_length} chars
      """
    end

    full_name
  end

  @spec generate_random_string(pos_integer()) :: String.t()
  def generate_random_string(length) do
    # Generate more bytes than needed to ensure we get enough characters after encoding
    byte_count = ceil(length * 5 / 8)

    :crypto.strong_rand_bytes(byte_count)
    |> Base.encode32(case: :lower, padding: false)
    |> String.slice(0..(length - 1))
  end
end
