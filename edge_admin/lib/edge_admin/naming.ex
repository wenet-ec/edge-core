# edge_admin/lib/edge_admin/naming.ex
defmodule EdgeAdmin.Naming do
  @moduledoc """
  Shared naming rules for resources whose identifiers travel through the
  Netmaker / WireGuard / SSH stacks.

  Centralised so every layer that validates a name (Layer 1 OpenApiSpex
  string pattern, Layer 1 MCP Peri regex, Layer 2 Form `validate_format`,
  Layer 4 Ecto schema `validate_format`, runtime checks in
  `EdgeAdmin.Vpn`) references the same constants. Validation passes stay
  independent (defense in depth); only the *patterns and length bounds*
  are shared.

  When tightening a rule, update here. The change automatically takes
  effect at every layer that imports it.

  ## Why two forms per pattern

  - `*_regex/0` returns a `~r//` literal — used by Peri, Ecto, Form,
    runtime `Regex.match?`.
  - `*_pattern/0` returns the inner regex string (no delimiters) — used
    by OpenApiSpex schemas via the `pattern:` field.

  These are derived from the same source string at compile time so they
  can't drift from each other.

  ## Patterns

  - **Cluster names** & **alias names** share a DNS-label charset:
    lowercase alphanumeric with hyphens, no leading/trailing hyphen.
    Different max lengths: clusters 24 (must fit Netmaker constraints),
    aliases 63 (DNS label maximum).
  - **SSH usernames** use a Unix-identifier charset: letter or
    underscore start, then alphanumerics / hyphens / underscores.
    3–32 chars.
  - **SSH public keys** match the OpenSSH public-key wire format:
    `<algorithm> <base64> [comment]`.
  """

  @dns_label_pattern "^[a-z0-9]([a-z0-9-]*[a-z0-9])?$"
  @dns_label_regex ~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/

  @ssh_username_pattern "^[a-z_][a-z0-9_-]*$"
  @ssh_username_regex ~r/^[a-z_][a-z0-9_-]*$/

  @ssh_public_key_pattern "^(ssh-ed25519|ecdsa-sha2-nistp(?:256|384|521)|ssh-rsa)\\s+([A-Za-z0-9+/]+=*)\\s*(.*)$"
  @ssh_public_key_regex ~r/^(ssh-ed25519|ecdsa-sha2-nistp(?:256|384|521)|ssh-rsa)\s+([A-Za-z0-9+\/]+=*)\s*(.*)$/

  # ── Cluster names ──────────────────────────────────────────────────────────

  @doc "Regex literal matching valid cluster names."
  def cluster_name_regex, do: @dns_label_regex

  @doc "Inner regex string for OpenApiSpex `pattern:` field."
  def cluster_name_pattern, do: @dns_label_pattern

  @doc "Maximum length of a cluster name. Bounded by Netmaker network-name limits."
  def cluster_name_max_length, do: 24

  # ── Alias names ────────────────────────────────────────────────────────────

  @doc "Regex literal matching valid alias names."
  def alias_name_regex, do: @dns_label_regex

  @doc "Inner regex string for OpenApiSpex `pattern:` field."
  def alias_name_pattern, do: @dns_label_pattern

  @doc "Minimum length of an alias name."
  def alias_name_min_length, do: 1

  @doc "Maximum length of an alias name. DNS label limit."
  def alias_name_max_length, do: 63

  # ── SSH usernames ──────────────────────────────────────────────────────────

  @doc "Regex literal matching valid SSH usernames."
  def ssh_username_regex, do: @ssh_username_regex

  @doc "Inner regex string for OpenApiSpex `pattern:` field."
  def ssh_username_pattern, do: @ssh_username_pattern

  @doc "Minimum length of an SSH username."
  def ssh_username_min_length, do: 3

  @doc "Maximum length of an SSH username."
  def ssh_username_max_length, do: 32

  # ── SSH public keys ────────────────────────────────────────────────────────

  @doc """
  Regex literal matching the OpenSSH public-key wire format
  (`<algorithm> <base64> [comment]`). Captures algorithm, base64 data,
  and (optional) comment.
  """
  def ssh_public_key_regex, do: @ssh_public_key_regex

  @doc "Inner regex string for OpenApiSpex `pattern:` field."
  def ssh_public_key_pattern, do: @ssh_public_key_pattern

  # ── SSH passwords ──────────────────────────────────────────────────────────

  @doc """
  Minimum length of an SSH password (when one is set — passwords are optional,
  key-only auth is supported). Shared across OpenApiSpex (Layer 1 REST), MCP
  Peri (Layer 1 MCP), and the Layer 2 Form `validate_length`.
  """
  def ssh_password_min_length, do: 12

  @doc "Maximum length of an SSH password."
  def ssh_password_max_length, do: 128
end
