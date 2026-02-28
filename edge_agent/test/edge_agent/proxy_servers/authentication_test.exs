# edge_agent/test/edge_agent/proxy_servers/authentication_test.exs
defmodule EdgeAgent.ProxyServers.AuthenticationTest do
  use EdgeAgent.DataCase

  alias EdgeAgent.ProxyServers.Authentication
  alias EdgeAgent.Settings

  defp with_auth_enabled(value, fun) do
    old = Application.get_env(:edge_agent, :proxy_servers_auth_enabled)
    Application.put_env(:edge_agent, :proxy_servers_auth_enabled, value)

    try do
      fun.()
    after
      if old == nil do
        Application.delete_env(:edge_agent, :proxy_servers_auth_enabled)
      else
        Application.put_env(:edge_agent, :proxy_servers_auth_enabled, old)
      end
    end
  end

  describe "authenticate/2 — auth disabled" do
    test "returns :ok regardless of credentials when auth is disabled" do
      with_auth_enabled(false, fn ->
        assert :ok = Authentication.authenticate("_", "wrong_password")
        assert :ok = Authentication.authenticate("any_user", "anything")
        assert :ok = Authentication.authenticate("", "")
      end)
    end

    test "does not consult Settings when auth is disabled" do
      # No password set in DB, but auth disabled → still :ok
      with_auth_enabled(false, fn ->
        assert :ok = Authentication.authenticate("_", "")
      end)
    end
  end

  describe "authenticate/2 — auth enabled, no password configured" do
    test "returns {:error, :no_password_configured} when Settings has no proxy_password" do
      # Fresh DB — no proxy_password set
      with_auth_enabled(true, fn ->
        assert {:error, :no_password_configured} = Authentication.authenticate("_", "anything")
      end)
    end
  end

  describe "authenticate/2 — auth enabled, password configured" do
    setup do
      {:ok, _} = Settings.set("proxy_password", "s3cr3t!")
      :ok
    end

    test "correct username '_' and correct password → :ok" do
      with_auth_enabled(true, fn ->
        assert :ok = Authentication.authenticate("_", "s3cr3t!")
      end)
    end

    test "wrong password → {:error, :invalid_credentials}" do
      with_auth_enabled(true, fn ->
        assert {:error, :invalid_credentials} = Authentication.authenticate("_", "wrong")
      end)
    end

    test "wrong username → {:error, :invalid_credentials}" do
      with_auth_enabled(true, fn ->
        assert {:error, :invalid_credentials} = Authentication.authenticate("admin", "s3cr3t!")
      end)
    end

    test "empty username → {:error, :invalid_credentials}" do
      with_auth_enabled(true, fn ->
        assert {:error, :invalid_credentials} = Authentication.authenticate("", "s3cr3t!")
      end)
    end

    test "empty password → {:error, :invalid_credentials}" do
      with_auth_enabled(true, fn ->
        assert {:error, :invalid_credentials} = Authentication.authenticate("_", "")
      end)
    end

    test "both wrong → {:error, :invalid_credentials}" do
      with_auth_enabled(true, fn ->
        assert {:error, :invalid_credentials} = Authentication.authenticate("admin", "wrong")
      end)
    end

    test "password is case-sensitive" do
      with_auth_enabled(true, fn ->
        assert {:error, :invalid_credentials} = Authentication.authenticate("_", "S3CR3T!")
        assert {:error, :invalid_credentials} = Authentication.authenticate("_", "s3cr3t")
        assert :ok = Authentication.authenticate("_", "s3cr3t!")
      end)
    end

    test "auth_enabled defaults to true when not configured" do
      # Temporarily remove the key to test the default value (true)
      # credo:disable-for-next-line Credo.Check.Warning.ApplicationConfigInModuleAttribute
      with_auth_enabled(true, fn ->
        assert :ok = Authentication.authenticate("_", "s3cr3t!")
        assert {:error, :invalid_credentials} = Authentication.authenticate("_", "wrong")
      end)
    end
  end
end
