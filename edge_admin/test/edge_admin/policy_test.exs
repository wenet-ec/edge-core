# edge_admin/test/edge_admin/policy_test.exs
defmodule EdgeAdmin.PolicyTest do
  use ExUnit.Case, async: true

  # Stub policy used to exercise the contract injected by `use EdgeAdmin.Policy`.
  # Defining it inside the test module keeps the test self-contained — no
  # dependency on any concrete domain policy.
  defmodule StubPolicy do
    @moduledoc false
    use EdgeAdmin.Policy

    @impl true
    def authorize?(:always_allow), do: true
    def authorize?(:always_deny), do: false
    def authorize?({:owner_check, owner_id, resource_owner_id}), do: owner_id == resource_owner_id
    def authorize?(_), do: false
  end

  describe "authorize/1" do
    test "boolean true → :ok" do
      assert StubPolicy.authorize(:always_allow) == :ok
    end

    test "boolean false → {:error, :forbidden}" do
      assert StubPolicy.authorize(:always_deny) == {:error, :forbidden}
    end

    test "tuple actions are passed through to authorize?/1" do
      assert StubPolicy.authorize({:owner_check, "user-1", "user-1"}) == :ok
      assert StubPolicy.authorize({:owner_check, "user-1", "user-2"}) == {:error, :forbidden}
    end

    test "unknown actions fall through to the catch-all clause (deny by default)" do
      assert StubPolicy.authorize(:unknown) == {:error, :forbidden}
    end

    test "the macro-injected behaviour is satisfied" do
      # Sanity check: any module that `use`s EdgeAdmin.Policy gets the
      # behaviour declaration. If this module compiled, the @behaviour
      # callback `authorize?/1` was honoured.
      assert function_exported?(StubPolicy, :authorize?, 1)
      assert function_exported?(StubPolicy, :authorize, 1)
    end
  end
end
