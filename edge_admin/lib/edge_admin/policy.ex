# edge_admin/lib/edge_admin/policy.ex
defmodule EdgeAdmin.Policy do
  @moduledoc """
  Lightweight authorization base module following the Bodyguard/Pundit convention.

  Policy modules `use EdgeAdmin.Policy` and implement boolean `authorize?/1` clauses
  per action. The base injects `authorize/1` which wraps the boolean into
  `:ok | {:error, :forbidden}` so call sites fit naturally into `with` pipelines.

  ## Defining a policy

      defmodule MyApp.Things.Policies.ThingPolicy do
        use EdgeAdmin.Policy

        def authorize?(:create), do: some_config_check()
        def authorize?(:delete), do: false
      end

  ## Calling a policy

      # In the controller — clean, no subject/resource noise in call site:
      with :ok <- ThingPolicy.authorize(:create) do
        ...
      end

  ## When subject/resource are needed

  Policy modules can define `authorize?/1` clauses that read whatever context they
  need internally (config, database, assigns). For ownership checks, accept the
  relevant structs directly:

      def authorize?({:update, node, execution}), do: node.id == execution.node_id

      # Call site:
      with :ok <- CommandExecutionPolicy.authorize({:update, node, execution}) do

  ## Migrating to Bodyguard

  Bodyguard expects `authorize(action, subject, resource)` on the policy module.
  Migration is purely additive — add that function, keep `authorize?` internally,
  switch call sites from `MyPolicy.authorize(action)` to `Bodyguard.permit(MyPolicy, ...)`.
  """

  @doc """
  Callback implemented by each policy module. Return `true` to allow, `false` to deny.
  Accepts any term as the action — use atoms for simple checks, tuples when context is needed.
  """
  @callback authorize?(action :: any()) :: boolean()

  defmacro __using__(_) do
    quote do
      @behaviour EdgeAdmin.Policy

      @doc """
      Authorizes the given action. Returns `:ok` or `{:error, :forbidden}`.
      """
      @spec authorize(any()) :: :ok | {:error, :forbidden}
      def authorize(action) do
        if authorize?(action), do: :ok, else: {:error, :forbidden}
      end
    end
  end
end
