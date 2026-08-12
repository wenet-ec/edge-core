# edge_admin/lib/edge_admin/form.ex
defmodule EdgeAdmin.Form do
  @moduledoc """
  Base module for input validation forms using Ecto embedded schemas.

  Forms validate and normalize external API input before it reaches contexts.
  They are the Layer 2 validation boundary; Ecto schemas remain responsible for
  canonical model integrity.
  """
  defmacro __using__(_) do
    quote do
      use Ecto.Schema

      import Ecto.Changeset

      @primary_key false
    end
  end
end
