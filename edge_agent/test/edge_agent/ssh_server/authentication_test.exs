# edge_agent/test/edge_agent/ssh_server/authentication_test.exs
defmodule EdgeAgent.SshServer.AuthenticationTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.SshServer.Authentication

  # ---------------------------------------------------------------------------
  # ssh_string/1 — RFC 4251 §5 length-prefixed string
  # ---------------------------------------------------------------------------

  describe "ssh_string/1" do
    test "prefixes a 4-byte big-endian length" do
      result = Authentication.ssh_string("ssh-rsa")

      assert <<7::32, "ssh-rsa">> = result
      assert byte_size(result) == 4 + 7
    end

    test "empty binary yields just the zero-length prefix" do
      assert Authentication.ssh_string("") == <<0::32>>
    end

    test "round-trip: length matches the body byte count" do
      for body <- ["a", "ssh-ed25519", String.duplicate("x", 1000)] do
        <<len::32, rest::binary>> = Authentication.ssh_string(body)
        assert len == byte_size(rest)
        assert rest == body
      end
    end
  end

  # ---------------------------------------------------------------------------
  # ssh_mpint/1 — RFC 4251 §5 multi-precision integer
  # ---------------------------------------------------------------------------

  describe "ssh_mpint/1" do
    test "0 → empty mpint (4-byte zero length, no body)" do
      assert Authentication.ssh_mpint(0) == <<0::32>>
    end

    test "small positive integer (high bit clear) — no leading 0x00" do
      # 1 → <<0,0,0,1, 1>>: length 1 byte, body 0x01.
      assert Authentication.ssh_mpint(1) == <<0, 0, 0, 1, 1>>
      assert Authentication.ssh_mpint(0x7F) == <<0, 0, 0, 1, 0x7F>>
    end

    test "high bit set — prepends 0x00 to keep positive sign" do
      # 0x80 alone would be interpreted as negative. Must prepend 0x00.
      assert Authentication.ssh_mpint(0x80) == <<0, 0, 0, 2, 0x00, 0x80>>
      assert Authentication.ssh_mpint(0xFF) == <<0, 0, 0, 2, 0x00, 0xFF>>
    end

    test "multi-byte integer with high bit clear in top byte — no padding" do
      # 0x7FFF → <<0, 0, 0, 2, 0x7F, 0xFF>>.
      assert Authentication.ssh_mpint(0x7FFF) == <<0, 0, 0, 2, 0x7F, 0xFF>>
    end

    test "multi-byte integer with high bit set in top byte — padding added" do
      # 0xFFFF → <<0, 0, 0, 3, 0x00, 0xFF, 0xFF>>.
      assert Authentication.ssh_mpint(0xFFFF) == <<0, 0, 0, 3, 0x00, 0xFF, 0xFF>>
    end

    test "RSA-typical exponent (65537 = 0x010001) — high bit clear, no padding" do
      assert Authentication.ssh_mpint(65_537) == <<0, 0, 0, 3, 0x01, 0x00, 0x01>>
    end
  end

  # ---------------------------------------------------------------------------
  # charlist_to_string/1
  # ---------------------------------------------------------------------------

  describe "charlist_to_string/1" do
    test "known SSH key types short-circuit to canonical strings" do
      assert Authentication.charlist_to_string(~c"ssh-rsa") == "ssh-rsa"
      assert Authentication.charlist_to_string(~c"ssh-dss") == "ssh-dss"
      assert Authentication.charlist_to_string(~c"ssh-ed25519") == "ssh-ed25519"
      assert Authentication.charlist_to_string(~c"ecdsa-sha2-nistp256") == "ecdsa-sha2-nistp256"
      assert Authentication.charlist_to_string(~c"ecdsa-sha2-nistp384") == "ecdsa-sha2-nistp384"
      assert Authentication.charlist_to_string(~c"ecdsa-sha2-nistp521") == "ecdsa-sha2-nistp521"
    end

    test "unknown charlists fall through to List.to_string" do
      assert Authentication.charlist_to_string(~c"future-algo") == "future-algo"
    end

    test "non-list input falls through to to_string/1" do
      assert Authentication.charlist_to_string("already-a-string") == "already-a-string"
    end
  end

  # ---------------------------------------------------------------------------
  # format_public_key/1 — five input shapes from :public_key / :ssh_file.
  # The output string is what admin compares against its allow-list, so drift
  # here breaks SSH authentication.
  # ---------------------------------------------------------------------------

  describe "format_public_key/1 — {key_type, key_data, comment} (ssh_file decode shape)" do
    test "renders as '<algorithm> <base64(key_data)>'" do
      result = Authentication.format_public_key({~c"ssh-ed25519", "raw-key-bytes", "comment"})

      assert result == "ssh-ed25519 #{Base.encode64("raw-key-bytes")}"
    end

    test "comment is intentionally dropped (admin doesn't store comments)" do
      key_data = "shared-bytes"

      a = Authentication.format_public_key({~c"ssh-ed25519", key_data, "alice@host"})
      b = Authentication.format_public_key({~c"ssh-ed25519", key_data, "bob@host"})

      assert a == b
    end

    test "uses charlist_to_string for the algorithm prefix" do
      result = Authentication.format_public_key({~c"ssh-rsa", "data", "x"})
      assert String.starts_with?(result, "ssh-rsa ")
    end
  end

  describe "format_public_key/1 — :RSAPublicKey (Erlang public_key module)" do
    test "encodes as the OpenSSH RSA wire format inside base64" do
      # exp=65537, mod=small for predictability.
      result = Authentication.format_public_key({:RSAPublicKey, 0x10001, 0x10001})

      assert String.starts_with?(result, "ssh-rsa ")

      "ssh-rsa " <> b64 = result
      decoded = Base.decode64!(b64)

      # Wire format: ssh_string("ssh-rsa") | ssh_mpint(exponent) | ssh_mpint(modulus).
      expected =
        <<7::32, "ssh-rsa">> <>
          <<0, 0, 0, 3, 0x01, 0x00, 0x01>> <>
          <<0, 0, 0, 3, 0x01, 0x00, 0x01>>

      assert decoded == expected
    end
  end

  describe "format_public_key/1 — Ed25519 (named curve OID 1.3.101.112)" do
    test "encodes as the OpenSSH ed25519 wire format inside base64" do
      point = String.duplicate(<<0xAB>>, 32)

      result =
        Authentication.format_public_key({{:ECPoint, point}, {:namedCurve, {1, 3, 101, 112}}})

      assert String.starts_with?(result, "ssh-ed25519 ")

      "ssh-ed25519 " <> b64 = result
      decoded = Base.decode64!(b64)

      # Wire format: ssh_string("ssh-ed25519") | ssh_string(point).
      expected =
        <<11::32, "ssh-ed25519">> <>
          <<32::32, point::binary>>

      assert decoded == expected
    end
  end

  describe "format_public_key/1 — {:\"ssh-ed25519\", key_data}" do
    test "wraps key data in 'ssh-ed25519 <base64>' (no extra wire framing)" do
      result = Authentication.format_public_key({:"ssh-ed25519", "raw-bytes"})
      assert result == "ssh-ed25519 #{Base.encode64("raw-bytes")}"
    end
  end

  describe "format_public_key/1 — pre-formatted binary" do
    test "trims and returns binary input as-is" do
      assert Authentication.format_public_key("ssh-ed25519 AAAAC3 user@host") ==
               "ssh-ed25519 AAAAC3 user@host"

      assert Authentication.format_public_key("  ssh-ed25519 AAAAC3 user@host  ") ==
               "ssh-ed25519 AAAAC3 user@host"
    end
  end

  describe "format_public_key/1 — unrecognised input" do
    test "returns empty string and logs a warning (refuses to authenticate)" do
      # auth_key?/2 checks for "" and rejects authentication. Returning
      # something cute (e.g. inspect(other)) would be a security hole.
      assert Authentication.format_public_key({:totally_unknown, "shape"}) == ""
      assert Authentication.format_public_key(nil) == ""
      assert Authentication.format_public_key(12_345) == ""
    end
  end
end
