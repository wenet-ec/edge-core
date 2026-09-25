# edge_agent/test/support/app_config.ex
defmodule EdgeAgent.Test.AppConfig do
  @moduledoc false

  @spec restore_on_exit(atom(), [atom()]) :: :ok
  def restore_on_exit(app, keys) do
    previous = Map.new(keys, &{&1, Elixir.Application.fetch_env(app, &1)})

    ExUnit.Callbacks.on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Elixir.Application.put_env(app, key, value)
        {key, :error} -> Elixir.Application.delete_env(app, key)
      end)
    end)

    :ok
  end
end
