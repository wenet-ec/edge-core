# edge_admin/lib/edge_admin/vpn/naming.ex
defmodule EdgeAdmin.Vpn.Naming do
  @moduledoc "Pure VPN name, network, domain, and hostname construction helpers."

  alias EdgeAdmin.Naming, as: CoreNaming

  def default_domain, do: Application.get_env(:edge_admin, :edge_vpn_default_domain, "nm.internal")

  @doc """
  Builds a VPN name with a prefix.

  Prefixes with `node-` by default or `admin-` with `prefix: :admin`.
  """
  @spec build_vpn_name(String.t(), keyword()) :: String.t()
  def build_vpn_name(name, opts \\ []) when is_binary(name) do
    prefix = Keyword.get(opts, :prefix, :node)

    case prefix do
      :node -> "node-#{name}"
      :admin -> "admin-#{name}"
    end
  end

  @doc """
  Builds a network name with a prefix.

  Prefixes with `cluster-` by default or `admin-cluster-` with
  `prefix: :admin`. Admin cluster suffixes are validated before construction.
  """
  @spec build_network_name(String.t(), keyword()) :: String.t()
  def build_network_name(name, opts \\ []) when is_binary(name) do
    prefix = Keyword.get(opts, :prefix, :node)

    case prefix do
      :node ->
        "cluster-#{name}"

      :admin ->
        validate_admin_cluster_suffix!(name)
        "admin-cluster-#{name}"
    end
  end

  @doc """
  Validates admin cluster name suffix.

  Raises ArgumentError if invalid.

  Rules:
  - Lowercase alphanumeric with hyphens
  - No leading/trailing hyphens
  - Total length with "admin-cluster-" prefix <= 32 chars
  """
  def validate_admin_cluster_suffix!(suffix) when is_binary(suffix) do
    prefix = "admin-cluster-"
    max_total_length = 32

    if !Regex.match?(CoreNaming.cluster_name_regex(), suffix) do
      raise ArgumentError, """
      Admin cluster name suffix must match format: lowercase alphanumeric with hyphens
      Got: #{suffix}
      """
    end

    full_name = "#{prefix}#{suffix}"

    if String.length(full_name) > max_total_length do
      max_suffix_length = max_total_length - String.length(prefix)

      raise ArgumentError, """
      Admin cluster name exceeds Netmaker's #{max_total_length} character limit
      Total: #{String.length(full_name)} chars
      Max suffix length: #{max_suffix_length} chars
      """
    end

    :ok
  end

  @doc """
  Builds a VPN domain from network name.
  """
  @spec build_vpn_domain(String.t(), String.t() | nil) :: String.t()
  def build_vpn_domain(network, domain \\ nil) do
    domain = domain || default_domain()

    case domain do
      "" -> network
      _ -> "#{network}.#{domain}"
    end
  end

  @doc """
  Builds a VPN hostname from components.
  """
  @spec build_vpn_hostname(String.t(), String.t(), String.t() | nil) :: String.t()
  def build_vpn_hostname(host, network, domain \\ nil) do
    "#{host}.#{build_vpn_domain(network, domain)}"
  end

  @doc """
  Builds an admin erlang node name from dns hostname.
  """
  def build_admin_erlang_node_name(hostname) do
    :"admin@#{hostname}"
  end

  @doc """
  Validates a network name for Netmaker compatibility.

  Validates:
  - Max 32 characters
  - Lowercase alphanumeric with hyphens
  - No leading/trailing hyphens
  """
  def validate_network_name(name) when is_binary(name) do
    cond do
      String.length(name) > 32 ->
        {:error, "network name exceeds 32 character limit"}

      not Regex.match?(CoreNaming.cluster_name_regex(), name) ->
        {:error, "network name must be lowercase alphanumeric with hyphens, no leading/trailing hyphens"}

      true ->
        :ok
    end
  end
end
