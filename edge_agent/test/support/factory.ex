# edge_agent/test/support/factory.ex
defmodule EdgeAgent.Factory do
  @moduledoc """
  Test data factories for EdgeAgent.
  """

  use ExMachina.Ecto, repo: EdgeAgent.Repo

  def name_factory do
    Faker.Person.name()
  end

  def email_factory do
    Faker.Internet.email()
  end

  def uuid_factory do
    Ecto.UUID.generate()
  end

  def api_request_params_factory do
    %{
      "data" => %{
        "type" => "test",
        "attributes" => %{
          "name" => Faker.Person.name(),
          "email" => Faker.Internet.email()
        }
      }
    }
  end

  def json_response_factory do
    %{
      "data" => %{
        "id" => Ecto.UUID.generate(),
        "type" => "test",
        "attributes" => build(:api_request_params)["data"]["attributes"]
      }
    }
  end
end
