# edge_agent/lib/edge_agent/ssh_server/config.ex
defmodule EdgeAgent.SshServer.Config do
  @moduledoc """
  SSH server configuration management.
  """

  @ssh_system_dir "/tmp/ssh_daemon"
  @ssh_user_dir "/tmp"

  @ssh_algorithms [
    kex: [
      :"ecdh-sha2-nistp384",
      :"ecdh-sha2-nistp521",
      :"ecdh-sha2-nistp256",
      :"diffie-hellman-group-exchange-sha256",
      :"diffie-hellman-group16-sha512",
      :"diffie-hellman-group18-sha512",
      :"diffie-hellman-group14-sha256"
    ],
    public_key: [
      :"ssh-ed25519",
      :"ecdsa-sha2-nistp384",
      :"ecdsa-sha2-nistp521",
      :"ecdsa-sha2-nistp256",
      :"rsa-sha2-256",
      :"rsa-sha2-512",
      :"ssh-rsa"
    ],
    cipher: [
      {:client2server,
       [
         :"aes256-gcm@openssh.com",
         :"aes256-ctr",
         :"aes192-ctr",
         :"aes128-gcm@openssh.com",
         :"aes128-ctr"
       ]},
      {:server2client,
       [
         :"aes256-gcm@openssh.com",
         :"aes256-ctr",
         :"aes192-ctr",
         :"aes128-gcm@openssh.com",
         :"aes128-ctr"
       ]}
    ],
    mac: [
      {:client2server, [:"hmac-sha2-256", :"hmac-sha2-512"]},
      {:server2client, [:"hmac-sha2-256", :"hmac-sha2-512"]}
    ]
  ]

  @supported_host_key_types [:"ssh-ed25519", :"ecdsa-sha2-nistp256", :"ssh-rsa"]

  def ssh_port, do: Application.get_env(:edge_agent, :ssh_port)
  def ssh_system_dir, do: @ssh_system_dir
  def ssh_user_dir, do: @ssh_user_dir
  def ssh_algorithms, do: @ssh_algorithms
  def supported_host_key_types, do: @supported_host_key_types

  def ssh_options(key_callback_module, shell_fun) do
    [
      {:ip, :any},
      {:system_dir, String.to_charlist(@ssh_system_dir)},
      {:user_dir, String.to_charlist(@ssh_user_dir)},
      {:key_cb, {key_callback_module, []}},
      {:auth_methods, ~c"publickey"},
      {:preferred_algorithms, @ssh_algorithms},
      {:shell, shell_fun}
    ]
  end
end
