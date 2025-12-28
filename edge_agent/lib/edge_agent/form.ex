# edge_agent/lib/edge_agent/form.ex
defmodule EdgeAgent.Form do
  @moduledoc """
  Base module for form objects in EdgeAgent.

  Provides common functionality for form validation and normalization.
  Forms act as an input validation boundary before data reaches domain models.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      import Ecto.Changeset

      @primary_key false
    end
  end
end
