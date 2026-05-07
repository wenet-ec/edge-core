# edge_admin/test/edge_admin/ssh/credential_matcher_test.exs
defmodule EdgeAdmin.Ssh.CredentialMatcherTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Ssh.CredentialMatcher
  alias EdgeAdmin.Ssh.Schemas.SshPublicKey
  alias EdgeAdmin.Ssh.Schemas.SshUsername

  # ---------------------------------------------------------------------------
  # check/3 — auth method semantics. The auth_method returned distinguishes
  # "wrong username" (:unknown) from "wrong credential" (:password / :public_key)
  # so the audit trail can tell them apart. Failure cases still return the
  # attempted method, not :unknown.
  # ---------------------------------------------------------------------------

  describe "check/3 — :unknown (no SshUsername record)" do
    test "nil ssh_username always returns {false, :unknown}" do
      assert CredentialMatcher.check(nil, "any-password", nil) == {false, :unknown}
      assert CredentialMatcher.check(nil, nil, "ssh-ed25519 AAAA") == {false, :unknown}
      assert CredentialMatcher.check(nil, "p", "k") == {false, :unknown}
      assert CredentialMatcher.check(nil, nil, nil) == {false, :unknown}
    end
  end

  describe "check/3 — :password" do
    test "user with no password_hash + supplied password → {false, :password}" do
      # Failure case still surfaces :password (intent: audit trail records the
      # attempted method, not just success).
      user = %SshUsername{password_hash: nil, ssh_public_keys: []}

      assert CredentialMatcher.check(user, "anything", nil) == {false, :password}
    end

    test "matching password → {true, :password}" do
      hash = Argon2.hash_pwd_salt("correct-horse-battery-staple")
      user = %SshUsername{password_hash: hash, ssh_public_keys: []}

      assert CredentialMatcher.check(user, "correct-horse-battery-staple", nil) ==
               {true, :password}
    end

    test "non-matching password → {false, :password}" do
      hash = Argon2.hash_pwd_salt("correct-horse-battery-staple")
      user = %SshUsername{password_hash: hash, ssh_public_keys: []}

      assert CredentialMatcher.check(user, "wrong-password", nil) == {false, :password}
    end
  end

  describe "check/3 — :public_key" do
    test "user with no stored keys + supplied key → {false, :public_key}" do
      user = %SshUsername{password_hash: nil, ssh_public_keys: []}

      assert CredentialMatcher.check(user, nil, "ssh-ed25519 AAAA user@host") ==
               {false, :public_key}
    end

    test "matching key → {true, :public_key}" do
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIabcdefghi user@host"
      user = %SshUsername{password_hash: nil, ssh_public_keys: [%SshPublicKey{public_key: key}]}

      assert CredentialMatcher.check(user, nil, key) == {true, :public_key}
    end

    test "match is comment-insensitive (re-pasting same key with different host suffix)" do
      stored = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIabcdefghi laptop"
      attempted = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIabcdefghi different-host"

      user = %SshUsername{
        password_hash: nil,
        ssh_public_keys: [%SshPublicKey{public_key: stored}]
      }

      assert CredentialMatcher.check(user, nil, attempted) == {true, :public_key}
    end

    test "match is comment-insensitive even when stored key has trailing whitespace" do
      stored = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIabcdefghi laptop  "
      attempted = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIabcdefghi"

      user = %SshUsername{
        password_hash: nil,
        ssh_public_keys: [%SshPublicKey{public_key: stored}]
      }

      assert CredentialMatcher.check(user, nil, attempted) == {true, :public_key}
    end

    test "different key data → {false, :public_key} even with matching algorithm + comment" do
      stored = "ssh-ed25519 AAAAA user@host"
      attempted = "ssh-ed25519 BBBBB user@host"

      user = %SshUsername{
        password_hash: nil,
        ssh_public_keys: [%SshPublicKey{public_key: stored}]
      }

      assert CredentialMatcher.check(user, nil, attempted) == {false, :public_key}
    end

    test "different algorithm → {false, :public_key}" do
      user = %SshUsername{
        password_hash: nil,
        ssh_public_keys: [%SshPublicKey{public_key: "ssh-ed25519 AAAAA"}]
      }

      assert CredentialMatcher.check(user, nil, "ssh-rsa AAAAA") == {false, :public_key}
    end

    test "any-of: matches if any stored key matches" do
      target_key = "ssh-ed25519 BBBBB user@host"

      user = %SshUsername{
        password_hash: nil,
        ssh_public_keys: [
          %SshPublicKey{public_key: "ssh-ed25519 AAAAA other"},
          %SshPublicKey{public_key: target_key},
          %SshPublicKey{public_key: "ssh-ed25519 CCCCC third"}
        ]
      }

      assert CredentialMatcher.check(user, nil, target_key) == {true, :public_key}
    end
  end

  describe "check/3 — password takes precedence over public_key when both are supplied" do
    test "password supplied → password path wins (public_key path skipped)" do
      # The function head order matters: password match is tried first when
      # password is non-nil, regardless of whether public_key is also supplied.
      hash = Argon2.hash_pwd_salt("right-pw")
      user = %SshUsername{password_hash: hash, ssh_public_keys: []}

      # Password is correct, public_key would be ignored even if it matched.
      assert CredentialMatcher.check(user, "right-pw", "ssh-ed25519 AAAAA") ==
               {true, :password}
    end
  end

  # ---------------------------------------------------------------------------
  # normalize_key/1 — strips trailing comment so re-pasting with a different
  # host suffix doesn't break matching.
  # ---------------------------------------------------------------------------

  describe "normalize_key/1" do
    test "strips comment, keeps algorithm + data" do
      assert CredentialMatcher.normalize_key("ssh-ed25519 AAAAA user@host") ==
               "ssh-ed25519 AAAAA"
    end

    test "preserves algorithm + data when no comment is present" do
      assert CredentialMatcher.normalize_key("ssh-ed25519 AAAAA") == "ssh-ed25519 AAAAA"
    end

    test "comment with embedded spaces is fully stripped" do
      # parts: 3 split — only the first space-separated token after data is the
      # boundary. Anything after that (including more spaces) is the comment.
      assert CredentialMatcher.normalize_key("ssh-rsa AAAA my full name comment") ==
               "ssh-rsa AAAA"
    end

    test "trims whitespace before splitting (well-formed but padded input still works)" do
      assert CredentialMatcher.normalize_key("  ssh-ed25519 AAAA user@host  ") ==
               "ssh-ed25519 AAAA"

      assert CredentialMatcher.normalize_key("  ssh-ed25519 AAAA  ") == "ssh-ed25519 AAAA"
    end

    test "single token / empty / padded-single-token falls through to trimmed input" do
      # Anything that doesn't produce at least <algorithm> <key_data> after
      # trimming returns the trimmed input — it can't match a well-formed
      # stored key, so we surface the input unchanged rather than
      # silently mangling it.
      assert CredentialMatcher.normalize_key("garbage") == "garbage"
      assert CredentialMatcher.normalize_key("  garbage  ") == "garbage"
      assert CredentialMatcher.normalize_key("") == ""
      assert CredentialMatcher.normalize_key("   ") == ""
    end
  end
end
