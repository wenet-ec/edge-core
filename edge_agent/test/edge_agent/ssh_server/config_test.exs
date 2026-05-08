# edge_agent/test/edge_agent/ssh_server/config_test.exs
defmodule EdgeAgent.SshServer.ConfigTest do
  use ExUnit.Case, async: true

  alias EdgeAgent.SshServer.Config

  # ---------------------------------------------------------------------------
  # supported_host_key_types — pinned list of algorithms we have keys for.
  # Drift here would let SSH advertise a key type whose private key isn't on
  # disk; signature verification would silently fail.
  # ---------------------------------------------------------------------------

  describe "supported_host_key_types/0" do
    test "is the documented set of algorithms we generate host keys for" do
      assert Config.supported_host_key_types() == [
               :"ssh-ed25519",
               :"ecdsa-sha2-nistp256",
               :"ssh-rsa"
             ]
    end
  end

  # ---------------------------------------------------------------------------
  # ssh_algorithms — KEX, public_key, cipher, MAC algorithm allow-lists.
  # These are security-sensitive: a deletion that weakens crypto, or an
  # addition that re-enables a known-broken algorithm, must be visible.
  # ---------------------------------------------------------------------------

  describe "ssh_algorithms/0" do
    test "exposes exactly the four algorithm categories" do
      assert Config.ssh_algorithms() |> Keyword.keys() |> Enum.sort() ==
               [:cipher, :kex, :mac, :public_key]
    end

    test "kex: pinned set" do
      assert Config.ssh_algorithms()[:kex] == [
               :"ecdh-sha2-nistp384",
               :"ecdh-sha2-nistp521",
               :"ecdh-sha2-nistp256",
               :"diffie-hellman-group-exchange-sha256",
               :"diffie-hellman-group16-sha512",
               :"diffie-hellman-group18-sha512",
               :"diffie-hellman-group14-sha256"
             ]
    end

    test "public_key: pinned set, aligned with supported_host_key_types/0" do
      pk = Config.ssh_algorithms()[:public_key]

      assert pk == [
               :"ssh-ed25519",
               :"ecdsa-sha2-nistp256",
               :"rsa-sha2-256",
               :"rsa-sha2-512",
               :"ssh-rsa"
             ]
    end

    test "cipher: same allow-list for both directions, only AES-CTR / AES-GCM" do
      ciphers = Config.ssh_algorithms()[:cipher]

      expected = [
        :"aes256-gcm@openssh.com",
        :"aes256-ctr",
        :"aes192-ctr",
        :"aes128-gcm@openssh.com",
        :"aes128-ctr"
      ]

      assert ciphers == [{:client2server, expected}, {:server2client, expected}]
    end

    test "cipher: no insecure modes (CBC / RC4 / 3DES / arcfour)" do
      # Defensive — drift is the security risk; pin that the allow-list does
      # not contain anything in the deny-list.
      forbidden = ~w(aes128-cbc aes192-cbc aes256-cbc 3des-cbc arcfour arcfour128 arcfour256)a

      ciphers =
        Enum.flat_map(Config.ssh_algorithms()[:cipher], fn {_dir, list} -> list end)

      for bad <- forbidden do
        refute bad in ciphers, "expected forbidden cipher #{inspect(bad)} not to be allowed"
      end
    end

    test "mac: same set for both directions, only SHA-2" do
      mac = Config.ssh_algorithms()[:mac]
      expected = [:"hmac-sha2-256", :"hmac-sha2-512"]

      assert mac == [{:client2server, expected}, {:server2client, expected}]
    end

    test "mac: no MD5 / SHA-1" do
      forbidden = ~w(hmac-md5 hmac-md5-96 hmac-sha1 hmac-sha1-96)a

      macs =
        Enum.flat_map(Config.ssh_algorithms()[:mac], fn {_dir, list} -> list end)

      for bad <- forbidden do
        refute bad in macs, "expected forbidden MAC #{inspect(bad)} not to be allowed"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # public_key list aligns with supported_host_key_types — the moduledoc
  # warns that drift here would advertise a key type whose private key isn't
  # on disk. Pin the alignment so a careless edit can't break it.
  # ---------------------------------------------------------------------------

  describe "public_key alignment with supported_host_key_types" do
    test "every supported_host_key_type appears in the public_key allow-list" do
      pk = Config.ssh_algorithms()[:public_key]

      for type <- Config.supported_host_key_types() do
        assert type in pk,
               "supported_host_key_type #{inspect(type)} should appear in ssh_algorithms[:public_key]"
      end
    end
  end
end
