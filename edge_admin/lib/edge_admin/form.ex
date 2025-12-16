# edge_admin/lib/edge_admin/form.ex
defmodule EdgeAdmin.Form do
  @moduledoc """
  Base module for input validation forms using Ecto embedded schemas.

  Forms handle input validation and normalization before passing data to contexts.
  They validate external API inputs while schemas validate model integrity.

  ## Usage

      defmodule MyApp.SomeForm do
        use EdgeAdmin.Form

        embedded_schema do
          field(:name, :string)
          field(:email, :string)
        end

        def changeset(params) do
          %__MODULE__{}
          |> cast(params, [:name, :email])
          |> validate_required([:name, :email])
          |> apply_action(:insert)
          |> case do
            {:ok, form} -> {:ok, to_map(form)}
            {:error, changeset} -> {:error, changeset}
          end
        end

        defp to_map(form), do: Map.from_struct(form)
      end
  """
  defmacro __using__(_) do
    quote do
      use Ecto.Schema

      import Ecto.Changeset

      @primary_key false
    end
  end
end
