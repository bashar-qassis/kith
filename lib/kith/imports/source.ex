defmodule Kith.Imports.Source do
  @moduledoc """
  Behaviour for import source plugins.

  Each source (VCard, Monica, etc.) implements this behaviour to define
  how to validate, parse, and import data from that source.
  """

  @type opts :: map()
  @type credential :: %{url: String.t(), api_key: String.t()}
  @type import_summary :: %{
          contacts: non_neg_integer(),
          notes: non_neg_integer(),
          skipped: non_neg_integer(),
          error_count: non_neg_integer(),
          errors: [String.t()]
        }

  @callback name() :: String.t()
  @callback file_types() :: [String.t()]
  @callback validate_file(binary()) :: {:ok, map()} | {:error, String.t()}
  @callback parse_summary(binary()) :: {:ok, map()} | {:error, String.t()}
  @callback import(account_id :: integer(), user_id :: integer(), data :: binary(), opts()) ::
              {:ok, import_summary()} | {:error, term()}
  @callback supports_api?() :: boolean()

  @callback test_connection(credential()) :: :ok | {:error, String.t()}
  @callback fetch_photo(credential(), resource_id :: String.t()) ::
              {:ok, binary()} | {:error, term()}
  @callback api_supplement_options() :: [
              %{key: atom(), label: String.t(), description: String.t()}
            ]
  @callback fetch_supplement(credential(), contact_source_id :: String.t(), key :: atom()) ::
              {:ok, map()} | {:error, term()}

  @optional_callbacks [test_connection: 1, fetch_photo: 2, api_supplement_options: 0, fetch_supplement: 3]
end
