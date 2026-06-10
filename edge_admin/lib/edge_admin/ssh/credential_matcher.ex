# edge_admin/lib/edge_admin/ssh/credential_matcher.ex
defmodule EdgeAdmin.Ssh.CredentialMatcher do
  @moduledoc """
  Pure credential-matching primitives for SSH authentication.

  Given a stored `SshUsername` (with preloaded `ssh_public_keys`) plus an
  attempted password OR public key, returns whether the attempt matches and
  which auth method was used. No DB calls, no telemetry, no events — those
  are orchestrated by `EdgeAdmin.Ssh.verify_ssh_credentials/2`.

  ## Auth method semantics

  - `:password` — a password was supplied, and we attempted a password match.
    Result reflects whether Argon2 verification succeeded.
  - `:public_key` — a public key was supplied, and we attempted to match it
    against the user's stored keys (after stripping the trailing comment).
    Result reflects whether any stored key matched.
  - `:unknown` — no `SshUsername` record was found for the attempted username
    on this node. We return this rather than `:password` / `:public_key` so
    the audit trail can distinguish "wrong username" from "wrong credential".

  Returning `:password` / `:public_key` for *failure* cases (e.g. password
  supplied but the user has no `password_hash`) is intentional — the audit
  trail wants to know which method the agent attempted, not just whether the
  match succeeded.
  """

  alias EdgeAdmin.Ssh.Schemas.SshUsername

  @type auth_method :: :password | :public_key | :unknown

  @doc """
  Verifies an SSH credential against a stored `SshUsername`.

  Returns `{verified?, auth_method}` — see moduledoc for the auth method
  semantics. Pass `nil` for `ssh_username` when no username record was found
  on the target node.
  """
  @spec check(SshUsername.t() | nil, String.t() | nil, String.t() | nil) ::
          {boolean(), auth_method()}
  def check(nil, _password, _public_key), do: {false, :unknown}

  def check(%SshUsername{password_hash: nil}, password, _) when not is_nil(password), do: {false, :password}

  def check(%SshUsername{password_hash: hash}, password, _) when not is_nil(password),
    do: {Argon2.verify_pass(password, hash), :password}

  def check(%SshUsername{ssh_public_keys: []}, _, public_key) when not is_nil(public_key), do: {false, :public_key}

  def check(%SshUsername{ssh_public_keys: keys}, _, public_key) when not is_nil(public_key) do
    provided_key_normalized = normalize_key(public_key)

    result =
      Enum.any?(keys, fn stored_key ->
        stored_key_normalized = stored_key.public_key |> String.trim() |> normalize_key()
        # Constant-time compare for uniformity with the password path. Public
        # keys aren't secret, so this is hardening rather than a fix, but it
        # avoids leaking how many leading bytes of a stored key an attempt matched.
        Plug.Crypto.secure_compare(provided_key_normalized, stored_key_normalized)
      end)

    {result, :public_key}
  end

  @doc """
  Normalizes an SSH key string by stripping the trailing comment, keeping only
  the algorithm and key data. Used to make key comparison comment-insensitive
  (so re-pasting the same key with a different host suffix still matches).

  Leading and trailing whitespace are stripped before splitting so callers
  don't get a nonsense `" "` result for whitespace-padded input. Inputs with
  fewer than two space-separated tokens (no key data present) fall through
  to the trimmed input — they can't match a well-formed stored key.
  """
  @spec normalize_key(String.t()) :: String.t()
  def normalize_key(key_string) do
    trimmed = String.trim(key_string)

    case String.split(trimmed, " ", parts: 3) do
      [algorithm, key_data, _comment] -> "#{algorithm} #{key_data}"
      [algorithm, key_data] -> "#{algorithm} #{key_data}"
      _ -> trimmed
    end
  end
end
