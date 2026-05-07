# edge_admin/test/edge_admin/naming_test.exs
defmodule EdgeAdmin.NamingTest do
  use ExUnit.Case, async: true

  alias EdgeAdmin.Naming

  # ---------------------------------------------------------------------------
  # Pattern / regex parity invariant — the moduledoc claims these are derived
  # from the same source string at compile time and "can't drift from each
  # other." Pin that explicitly: compile each pattern string and compare.
  # ---------------------------------------------------------------------------

  describe "pattern ↔ regex parity" do
    test "cluster_name_pattern compiles to cluster_name_regex" do
      assert Regex.source(Naming.cluster_name_regex()) == Naming.cluster_name_pattern()
    end

    test "alias_name_pattern compiles to alias_name_regex" do
      assert Regex.source(Naming.alias_name_regex()) == Naming.alias_name_pattern()
    end

    test "ssh_username_pattern compiles to ssh_username_regex" do
      assert Regex.source(Naming.ssh_username_regex()) == Naming.ssh_username_pattern()
    end

    test "ssh_public_key_pattern compiles to ssh_public_key_regex" do
      assert Regex.source(Naming.ssh_public_key_regex()) == Naming.ssh_public_key_pattern()
    end

    test "cluster and alias share the same DNS-label regex" do
      # Both patterns/regexes intentionally point at the shared @dns_label.
      # Compare sources, not Regex structs — the compiled :re_pattern field
      # holds a unique Reference per compile, so structural == always fails.
      assert Regex.source(Naming.cluster_name_regex()) ==
               Regex.source(Naming.alias_name_regex())

      assert Naming.cluster_name_pattern() == Naming.alias_name_pattern()
    end
  end

  # ---------------------------------------------------------------------------
  # DNS-label charset (cluster + alias names): lowercase alphanumeric with
  # hyphens, no leading or trailing hyphen.
  # ---------------------------------------------------------------------------

  describe "cluster_name_regex/0 — DNS label charset" do
    test "accepts lowercase alphanumerics and internal hyphens" do
      for name <- ~w(a abc abc123 a-b a-b-c prod-1 cluster-test-2 0 9-0) do
        assert Regex.match?(Naming.cluster_name_regex(), name),
               "expected #{inspect(name)} to be valid"
      end
    end

    test "rejects leading/trailing hyphens" do
      for name <- ~w(-abc abc- -abc- -) do
        refute Regex.match?(Naming.cluster_name_regex(), name),
               "expected #{inspect(name)} to be rejected"
      end
    end

    test "rejects uppercase, underscores, dots, whitespace, and other punctuation" do
      for name <- ["ABC", "Abc", "abc_def", "abc.def", "abc/def", "abc:def", "abc def"] do
        refute Regex.match?(Naming.cluster_name_regex(), name),
               "expected #{inspect(name)} to be rejected"
      end
    end

    test "rejects empty string" do
      refute Regex.match?(Naming.cluster_name_regex(), "")
    end
  end

  describe "cluster_name_max_length/0" do
    test "is 24 (Netmaker constraint)" do
      assert Naming.cluster_name_max_length() == 24
    end
  end

  describe "alias_name length bounds" do
    test "min is 1, max is 63 (DNS label limit)" do
      assert Naming.alias_name_min_length() == 1
      assert Naming.alias_name_max_length() == 63
    end
  end

  # ---------------------------------------------------------------------------
  # SSH username charset: letter or underscore start, then alphanumerics /
  # hyphens / underscores. (Lowercase only.)
  # ---------------------------------------------------------------------------

  describe "ssh_username_regex/0" do
    test "accepts the documented charset" do
      for name <- ~w(a _user user_name user-name u123 _ a_b-c-d) do
        assert Regex.match?(Naming.ssh_username_regex(), name),
               "expected #{inspect(name)} to be valid"
      end
    end

    test "rejects leading digit or hyphen" do
      for name <- ~w(1user -user 9 -) do
        refute Regex.match?(Naming.ssh_username_regex(), name),
               "expected #{inspect(name)} to be rejected"
      end
    end

    test "rejects uppercase and other punctuation" do
      for name <- ~w(User USER user.name user@host user/x) do
        refute Regex.match?(Naming.ssh_username_regex(), name),
               "expected #{inspect(name)} to be rejected"
      end
    end

    test "rejects empty string" do
      refute Regex.match?(Naming.ssh_username_regex(), "")
    end
  end

  describe "ssh_username length bounds" do
    test "min is 3, max is 32" do
      assert Naming.ssh_username_min_length() == 3
      assert Naming.ssh_username_max_length() == 32
    end
  end

  # ---------------------------------------------------------------------------
  # SSH public key wire format: <algorithm> <base64> [comment]
  # ---------------------------------------------------------------------------

  describe "ssh_public_key_regex/0" do
    test "accepts ed25519, RSA, and ECDSA algorithms" do
      assert Regex.match?(
               Naming.ssh_public_key_regex(),
               "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIabcdefghijklmnopqrstuvwxyz user@host"
             )

      assert Regex.match?(
               Naming.ssh_public_key_regex(),
               "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ== user@host"
             )

      assert Regex.match?(
               Naming.ssh_public_key_regex(),
               "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTY= host"
             )

      assert Regex.match?(
               Naming.ssh_public_key_regex(),
               "ecdsa-sha2-nistp384 AAAAE2VjZHNh="
             )

      assert Regex.match?(
               Naming.ssh_public_key_regex(),
               "ecdsa-sha2-nistp521 AAAAE2VjZHNh="
             )
    end

    test "comment is optional" do
      assert Regex.match?(Naming.ssh_public_key_regex(), "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5")
    end

    test "rejects unknown algorithms" do
      refute Regex.match?(Naming.ssh_public_key_regex(), "ssh-dss AAAAB3NzaC1kc3M=")
      refute Regex.match?(Naming.ssh_public_key_regex(), "rsa AAAAB3NzaC1yc2E=")

      # Wrong nistp curve.
      refute Regex.match?(Naming.ssh_public_key_regex(), "ecdsa-sha2-nistp192 AAAAE=")
    end

    test "rejects malformed inputs" do
      refute Regex.match?(Naming.ssh_public_key_regex(), "")
      # Algorithm only — no whitespace + key data.
      refute Regex.match?(Naming.ssh_public_key_regex(), "ssh-ed25519")
      # Algorithm followed by whitespace but no key data — `\s+` consumes the
      # spaces and the data class `[A-Za-z0-9+/]+` requires at least one char.
      refute Regex.match?(Naming.ssh_public_key_regex(), "ssh-ed25519  ")
      # Key body must start with at least one base64 char immediately after
      # the whitespace — leading punctuation breaks it.
      refute Regex.match?(Naming.ssh_public_key_regex(), "ssh-ed25519 !nope")
    end

    test "captures algorithm, key data, and comment" do
      [_full, algo, data, comment] =
        Regex.run(
          Naming.ssh_public_key_regex(),
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5= alice@laptop"
        )

      assert algo == "ssh-ed25519"
      assert data == "AAAAC3NzaC1lZDI1NTE5="
      assert comment == "alice@laptop"
    end
  end
end
