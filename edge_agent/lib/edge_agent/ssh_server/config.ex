# edge_agent/lib/edge_agent/ssh_server/config.ex
defmodule EdgeAgent.SshServer.Config do
  @moduledoc """
  SSH server configuration management.

  `ssh_system_dir` and `ssh_user_dir` are derived from the agent-wide
  `DATA_DIR` in `runtime.exs`, so SSH host keys live alongside SQLite and
  Edge VPN CLI state on the persistent volume — they survive container
  restarts. The `users` subdirectory is required by `:ssh.daemon`'s
  `:user_dir` option but is otherwise unused (we delegate authentication
  to admin via `EdgeAgent.SshServer.Authentication`, not authorized_keys
  files).
  """

  # Note on host-key algorithms: we generate exactly one ECDSA key (P-256)
  # via OpenSSL's `prime256v1` curve. Listing P-384/P-521 here would let SSH
  # negotiate them, but `HostKeys.host_key/1` returns the P-256 key for all
  # ECDSA variants — wrong curve, signature won't validate. Keep the
  # public_key list aligned with the keys we actually own.
  # KEX algorithms are independent of host-key algorithms.
  @ssh_algorithms [
    kex: [
      :"mlkem768x25519-sha256",
      :"curve25519-sha256",
      :"curve25519-sha256@libssh.org",
      :"curve448-sha512",
      :"ecdh-sha2-nistp521",
      :"ecdh-sha2-nistp384",
      :"ecdh-sha2-nistp256",
      :"diffie-hellman-group-exchange-sha256",
      :"diffie-hellman-group16-sha512",
      :"diffie-hellman-group18-sha512",
      :"diffie-hellman-group14-sha256"
    ],
    public_key: [
      :"ssh-ed25519",
      :"ecdsa-sha2-nistp256",
      :"rsa-sha2-512",
      :"rsa-sha2-256",
      :"ssh-rsa"
    ],
    cipher: [
      {:client2server,
       [
         :"aes256-gcm@openssh.com",
         :"aes256-ctr",
         :"aes192-ctr",
         :"aes128-gcm@openssh.com",
         :"aes128-ctr",
         :"chacha20-poly1305@openssh.com"
       ]},
      {:server2client,
       [
         :"aes256-gcm@openssh.com",
         :"aes256-ctr",
         :"aes192-ctr",
         :"aes128-gcm@openssh.com",
         :"aes128-ctr",
         :"chacha20-poly1305@openssh.com"
       ]}
    ],
    mac: [
      {:client2server,
       [
         :"hmac-sha2-512-etm@openssh.com",
         :"hmac-sha2-256-etm@openssh.com",
         :"hmac-sha2-512",
         :"hmac-sha2-256"
       ]},
      {:server2client,
       [
         :"hmac-sha2-512-etm@openssh.com",
         :"hmac-sha2-256-etm@openssh.com",
         :"hmac-sha2-512",
         :"hmac-sha2-256"
       ]}
    ]
  ]

  @supported_host_key_types [:"ssh-ed25519", :"ecdsa-sha2-nistp256", :"ssh-rsa"]

  @doc "Returns the configured SSH listening port."
  @spec ssh_port() :: non_neg_integer() | nil
  def ssh_port, do: Application.get_env(:edge_agent, :ssh_port)

  @doc "Returns the directory containing persistent SSH host keys."
  @spec ssh_system_dir() :: String.t()
  def ssh_system_dir, do: Application.fetch_env!(:edge_agent, :ssh_system_dir)

  @doc "Returns the SSH user directory passed to the Erlang SSH daemon."
  @spec ssh_user_dir() :: String.t()
  def ssh_user_dir, do: Application.fetch_env!(:edge_agent, :ssh_user_dir)

  @doc "Returns the preferred SSH algorithm configuration."
  @spec ssh_algorithms() :: keyword()
  def ssh_algorithms, do: @ssh_algorithms

  @doc "Returns the host-key algorithms supported by the Agent SSH server."
  @spec supported_host_key_types() :: [atom()]
  def supported_host_key_types, do: @supported_host_key_types

  @doc "Builds the Erlang SSH daemon options for the Agent server."
  @spec ssh_options(module(), function()) :: keyword()
  def ssh_options(key_callback_module, password_callback) do
    [
      # An IPv6 wildcard socket with v6-only disabled accepts both overlay
      # families on supported Linux hosts. SSH has no separate proxy layer to
      # provide this fallback, so it must listen dual-stack itself.
      :inet6,
      {:ip, {0, 0, 0, 0, 0, 0, 0, 0}},
      {:ipv6_v6only, false},
      {:system_dir, String.to_charlist(ssh_system_dir())},
      {:user_dir, String.to_charlist(ssh_user_dir())},
      {:key_cb, {key_callback_module, []}},
      {:pwdfun, password_callback},
      {:auth_methods, ~c"publickey,password"},
      {:preferred_algorithms, @ssh_algorithms},
      {:parallel_login, true},
      {:subsystems, []},
      {:ssh_cli, {EdgeAgent.SshServer.Channel, []}}
    ]
  end
end
