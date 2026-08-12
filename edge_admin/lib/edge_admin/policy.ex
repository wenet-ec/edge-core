# edge_admin/lib/edge_admin/policy.ex
defmodule EdgeAdmin.Policy do
  @moduledoc """
  Lightweight authorization base module following the Bodyguard/Pundit convention.

  Policy modules implement boolean `authorize?/1` clauses. The base injects
  `authorize/1`, which wraps the boolean result as `:ok | {:error, :forbidden}`
  for use in `with` pipelines. Actions may be atoms or tuples carrying whatever
  context the policy needs.
  """

  @doc """
  Callback implemented by each policy module.

  Return `true` to allow, `false` to deny.
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
