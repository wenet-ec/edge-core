# edge_admin/lib/edge_admin/events/webhooks/ssrf.ex
defmodule EdgeAdmin.Events.Webhooks.Ssrf do
  @moduledoc """
  SSRF defence-in-depth checks for webhook destinations.

  Enabled by default in production. Operators can opt out per-deployment with
  `WEBHOOK_ALLOW_PRIVATE_IPS=true` for homelab / dev where webhook receivers
  legitimately live on RFC1918 ranges.

  Checks the URL host at config-time (create / update). Does **not** re-check
  per-request — that would defend against DNS-rebinding attacks but require
  pinning the resolved IP for the actual HTTP call. Out of scope; operators
  should use network-layer egress controls if rebinding is a concern.

  ## Default deny list

  Loopback, link-local, RFC1918 / ULA, multicast, the unspecified address,
  and well-known cloud-metadata endpoints (AWS, GCP, Azure, Aliyun, Tencent).

  Resolves the hostname and checks **every** returned A/AAAA record against
  the deny list — a public-looking hostname that resolves to `127.0.0.1`
  is denied. IPv4-mapped IPv6 (`::ffff:a.b.c.d`) is normalized to its IPv4
  tuple before matching, so attackers cannot bypass with the v6 form.

  Userinfo (`user:pass@host`) and URL fragments are rejected outright as part
  of `validate_url/1` — they're not a security threat, but they're consistent
  hygiene and accidentally leak credentials into logs.
  """

  import Bitwise

  @deny_cidrs_v4 [
    {{127, 0, 0, 0}, 8},
    {{169, 254, 0, 0}, 16},
    {{10, 0, 0, 0}, 8},
    {{172, 16, 0, 0}, 12},
    {{192, 168, 0, 0}, 16},
    {{0, 0, 0, 0}, 32},
    {{224, 0, 0, 0}, 4},
    # Aliyun metadata service
    {{100, 100, 100, 200}, 32}
  ]

  @deny_cidrs_v6 [
    {{0, 0, 0, 0, 0, 0, 0, 1}, 128},
    {{0xFE80, 0, 0, 0, 0, 0, 0, 0}, 10},
    {{0xFC00, 0, 0, 0, 0, 0, 0, 0}, 7},
    {{0xFF00, 0, 0, 0, 0, 0, 0, 0}, 8}
  ]

  @deny_hosts [
    "metadata.google.internal",
    "metadata.azure.internal",
    "metadata.tencentyun.com"
  ]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Validates a URL string. Returns `:ok` or `{:error, reason_atom_or_tuple}`.

  Reasons:
    - `:invalid_url`            — not parseable / missing scheme or host
    - `:userinfo_not_allowed`   — `user:pass@` form rejected
    - `:fragment_not_allowed`   — fragments rejected
    - `{:denied_host, host}`    — exact-match block on a metadata hostname
    - `{:denied, host, ip}`     — host or one of its resolved IPs is in the deny list

  Skipped entirely (returns `:ok`) when `WEBHOOK_ALLOW_PRIVATE_IPS=true`.
  """
  @spec validate_url(String.t()) ::
          :ok
          | {:error,
             :invalid_url
             | :userinfo_not_allowed
             | :fragment_not_allowed
             | {:denied_host, String.t()}
             | {:denied, String.t(), :inet.ip_address()}}
  def validate_url(url) when is_binary(url) do
    %URI{scheme: scheme, host: host, userinfo: userinfo, fragment: fragment} = URI.parse(url)

    with :ok <- check_scheme(scheme),
         :ok <- check_host_present(host),
         :ok <- check_userinfo(userinfo),
         :ok <- check_fragment(fragment) do
      if enabled?(), do: check_host(host), else: :ok
    end
  end

  def validate_url(_), do: {:error, :invalid_url}

  @doc """
  Whether SSRF checks are enabled. Defaults to true; operators opt out with
  `WEBHOOK_ALLOW_PRIVATE_IPS=true`.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    not Application.get_env(:edge_admin, :webhook_allow_private_ips, false)
  end

  @doc """
  Human-readable error message for a `validate_url/1` error reason.
  """
  @spec format_error(term()) :: String.t()
  def format_error(:invalid_url), do: "URL is not a valid absolute http(s) URL"
  def format_error(:userinfo_not_allowed), do: "URL must not include userinfo (user:pass@host)"
  def format_error(:fragment_not_allowed), do: "URL must not include a fragment"
  def format_error({:denied_host, host}), do: "host #{host} is on the SSRF deny list"

  def format_error({:denied, host, ip}) do
    "host #{host} resolves to #{:inet.ntoa(ip)} which is in a denied range"
  end

  def format_error(other), do: inspect(other)

  # ---------------------------------------------------------------------------
  # Internal
  # ---------------------------------------------------------------------------

  defp check_scheme(scheme) when scheme in ["http", "https"], do: :ok
  defp check_scheme(_), do: {:error, :invalid_url}

  defp check_host_present(host) when is_binary(host) and host != "", do: :ok
  defp check_host_present(_), do: {:error, :invalid_url}

  defp check_userinfo(nil), do: :ok
  defp check_userinfo(_), do: {:error, :userinfo_not_allowed}

  defp check_fragment(nil), do: :ok
  defp check_fragment(_), do: {:error, :fragment_not_allowed}

  defp check_host(host) do
    normalized = normalize_host(host)

    if normalized in @deny_hosts do
      {:error, {:denied_host, host}}
    else
      case parse_ip_literal(normalized) do
        {:ok, ip} -> check_ip(host, ip)
        :not_an_ip -> resolve_and_check(host, normalized)
      end
    end
  end

  defp normalize_host(host) do
    host |> String.downcase() |> String.trim_trailing(".")
  end

  defp parse_ip_literal(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} -> {:ok, normalize_mapped(ip)}
      {:error, _} -> :not_an_ip
    end
  end

  # IPv4-mapped IPv6 (::ffff:a.b.c.d) → IPv4. Without this normalization, the
  # v6 form bypasses the v4 deny list.
  defp normalize_mapped({0, 0, 0, 0, 0, 0xFFFF, ab, cd}) do
    {ab >>> 8 &&& 0xFF, ab &&& 0xFF, cd >>> 8 &&& 0xFF, cd &&& 0xFF}
  end

  defp normalize_mapped(ip), do: ip

  defp resolve_and_check(host, normalized) do
    host_charlist = String.to_charlist(normalized)
    v4 = resolve(host_charlist, :inet)
    v6 = resolve(host_charlist, :inet6)
    ips = Enum.map(v4 ++ v6, &normalize_mapped/1)

    case Enum.find(ips, &denied_ip?/1) do
      nil -> :ok
      ip -> {:error, {:denied, host, ip}}
    end
  end

  defp resolve(host_charlist, family) do
    case :inet.getaddrs(host_charlist, family) do
      {:ok, ips} -> ips
      {:error, _} -> []
    end
  end

  defp check_ip(host, ip) do
    if denied_ip?(ip) do
      {:error, {:denied, host, ip}}
    else
      :ok
    end
  end

  defp denied_ip?(ip) when tuple_size(ip) == 4 do
    Enum.any?(@deny_cidrs_v4, fn cidr -> in_cidr?(ip, cidr) end)
  end

  defp denied_ip?(ip) when tuple_size(ip) == 8 do
    Enum.any?(@deny_cidrs_v6, fn cidr -> in_cidr?(ip, cidr) end)
  end

  defp denied_ip?(_), do: false

  defp in_cidr?(ip, {cidr_ip, prefix}) when tuple_size(ip) == tuple_size(cidr_ip) do
    ip_int = ip_to_int(ip)
    cidr_int = ip_to_int(cidr_ip)
    shift = bits(ip) - prefix
    ip_int >>> shift == cidr_int >>> shift
  end

  defp in_cidr?(_, _), do: false

  defp bits(ip) when tuple_size(ip) == 4, do: 32
  defp bits(ip) when tuple_size(ip) == 8, do: 128

  defp ip_to_int({a, b, c, d}) do
    a <<< 24 ||| b <<< 16 ||| c <<< 8 ||| d
  end

  defp ip_to_int({a, b, c, d, e, f, g, h}) do
    a <<< 112 ||| b <<< 96 ||| c <<< 80 ||| d <<< 64 |||
      e <<< 48 ||| f <<< 32 ||| g <<< 16 ||| h
  end
end
