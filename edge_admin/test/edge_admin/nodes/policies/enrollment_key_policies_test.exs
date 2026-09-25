# edge_admin/test/edge_admin/nodes/policies/enrollment_key_policies_test.exs
defmodule EdgeAdmin.Nodes.Policies.EnrollmentKeyPoliciesTest do
  # async: false because tests mutate :default_cluster_name and
  # :public_enrollment_key_enabled. The policy reads them on every call,
  # so racing test writes would cross-talk between cases.
  use ExUnit.Case, async: false

  alias EdgeAdmin.Nodes.Policies.EnrollmentKeyPolicies
  alias EdgeAdmin.Test.AppConfig

  setup do
    AppConfig.restore_on_exit(:edge_admin, [:default_cluster_name, :public_enrollment_key_enabled])

    :ok
  end

  # :create_for_default — allowed iff default_cluster_name is a binary

  describe "authorize/1 — :create_for_default" do
    test "allowed when default_cluster_name is a binary" do
      Elixir.Application.put_env(:edge_admin, :default_cluster_name, "default")

      assert EnrollmentKeyPolicies.authorize(:create_for_default) == :ok
    end

    test "denied when default_cluster_name is unset" do
      Elixir.Application.delete_env(:edge_admin, :default_cluster_name)

      assert EnrollmentKeyPolicies.authorize(:create_for_default) == {:error, :forbidden}
    end

    test "denied when default_cluster_name is nil" do
      Elixir.Application.put_env(:edge_admin, :default_cluster_name, nil)

      assert EnrollmentKeyPolicies.authorize(:create_for_default) == {:error, :forbidden}
    end

    test "denied for non-binary default_cluster_name (defensive)" do
      # Operators can technically misconfigure this. The is_binary/1 guard
      # ensures we don't accept atoms or other types as 'set'.
      Elixir.Application.put_env(:edge_admin, :default_cluster_name, :default)

      assert EnrollmentKeyPolicies.authorize(:create_for_default) == {:error, :forbidden}
    end
  end

  # :create_for_public — allowed iff public_enrollment_key_enabled == true
  #                                  AND default_cluster_name is a binary

  describe "authorize/1 — :create_for_public" do
    test "allowed when both flags are set" do
      Elixir.Application.put_env(:edge_admin, :default_cluster_name, "default")
      Elixir.Application.put_env(:edge_admin, :public_enrollment_key_enabled, true)

      assert EnrollmentKeyPolicies.authorize(:create_for_public) == :ok
    end

    test "denied when public flag is false even if default cluster is set" do
      Elixir.Application.put_env(:edge_admin, :default_cluster_name, "default")
      Elixir.Application.put_env(:edge_admin, :public_enrollment_key_enabled, false)

      assert EnrollmentKeyPolicies.authorize(:create_for_public) == {:error, :forbidden}
    end

    test "denied when public flag is unset (defaults to false)" do
      Elixir.Application.put_env(:edge_admin, :default_cluster_name, "default")
      Elixir.Application.delete_env(:edge_admin, :public_enrollment_key_enabled)

      assert EnrollmentKeyPolicies.authorize(:create_for_public) == {:error, :forbidden}
    end

    test "denied when default cluster is unset even if public flag is true" do
      Elixir.Application.delete_env(:edge_admin, :default_cluster_name)
      Elixir.Application.put_env(:edge_admin, :public_enrollment_key_enabled, true)

      assert EnrollmentKeyPolicies.authorize(:create_for_public) == {:error, :forbidden}
    end

    test "denied for non-true public flag values (defensive)" do
      # The == true guard rejects truthy-but-not-true values (e.g. atom or string).
      Elixir.Application.put_env(:edge_admin, :default_cluster_name, "default")
      Elixir.Application.put_env(:edge_admin, :public_enrollment_key_enabled, "true")

      assert EnrollmentKeyPolicies.authorize(:create_for_public) == {:error, :forbidden}
    end
  end

  # Catch-all — unknown actions deny by default

  describe "authorize/1 — unknown actions" do
    test "unknown atom action is denied" do
      assert EnrollmentKeyPolicies.authorize(:something_else) == {:error, :forbidden}
    end

    test "unknown tuple action is denied" do
      assert EnrollmentKeyPolicies.authorize({:create_for_unknown, "foo"}) == {:error, :forbidden}
    end
  end
end
