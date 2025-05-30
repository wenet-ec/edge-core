# test/support/factory.ex
defmodule EdgeAdmin.Factory do
  @moduledoc """
  Test data factories for EdgeAdmin.

  This module provides factory functions for creating test data.
  Use `build/2` for structs and `insert/2` for database records.
  """

  use ExMachina.Ecto, repo: EdgeAdmin.Repo

  # Keep the existing name factory but make it more useful
  def name_factory do
    Faker.Person.name()
  end

  # Add more useful factories for API testing
  def email_factory do
    Faker.Internet.email()
  end

  def uuid_factory do
    Ecto.UUID.generate()
  end

  # Example user factory (if you add user models later)
  # def user_factory do
  #   %EdgeAdmin.Users.User{
  #     id: Ecto.UUID.generate(),
  #     email: sequence(:email, &"user#{&1}@example.com"),
  #     name: Faker.Person.name(),
  #     inserted_at: DateTime.utc_now(),
  #     updated_at: DateTime.utc_now()
  #   }
  # end

  # API request factories for testing
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
