defmodule KithWeb.API.Includes do
  @moduledoc """
  Parses and validates the `?include=` query parameter for compound document support.

  Each resource type defines its valid includes. If an unknown include is requested,
  returns an error with the valid options listed.

  ## Usage

      case parse_includes(params, :contact_show) do
        {:ok, includes} -> # list of atoms like [:tags, :notes]
        {:error, detail} -> # error message string for 400 response
      end
  """

  @valid_includes %{
    contact_show:
      ~w(tags contact_fields addresses notes life_events activities calls relationships reminders documents photos),
    contact_list: ~w(tags contact_fields addresses),
    note: [],
    activity: ~w(contacts),
    reminder: ~w(contact),
    account: ~w(users reminder_rules custom_genders custom_field_types custom_relationship_types)
  }

  @doc """
  Parses the `include` query parameter for the given resource type.

  Returns `{:ok, include_list}` where include_list is a list of atom keys,
  or `{:error, detail_message}` for invalid includes.
  """
  @spec parse_includes(map(), atom()) :: {:ok, [atom()]} | {:error, String.t()}
  def parse_includes(params, resource_type) do
    valid = Map.get(@valid_includes, resource_type, [])

    case params["include"] do
      nil ->
        {:ok, []}

      "" ->
        {:ok, []}

      include_str when is_binary(include_str) ->
        requested =
          include_str
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.map(&String.downcase/1)
          |> Enum.reject(&(&1 == ""))

        invalid = requested -- valid

        if invalid == [] do
          {:ok, Enum.map(requested, &String.to_existing_atom/1)}
        else
          resource_name = resource_type |> Atom.to_string() |> String.replace("_", " ")

          {:error,
           "Invalid include '#{Enum.join(invalid, ", ")}'. " <>
             "Valid includes for #{resource_name} are: #{Enum.join(valid, ", ")}."}
        end
    end
  rescue
    ArgumentError ->
      {:error, "Invalid include value."}
  end

  @doc """
  Converts a list of include atoms to Ecto preload specs.
  """
  @spec to_preloads([atom()]) :: [atom()]
  def to_preloads(includes) do
    Enum.flat_map(includes, fn
      :contact_fields -> [:contact_fields]
      :life_events -> [:life_events]
      :custom_genders -> [:genders]
      :custom_field_types -> [:contact_field_types]
      :custom_relationship_types -> [:relationship_types]
      :reminder_rules -> [:reminder_rules]
      other -> [other]
    end)
  end

  @doc """
  Returns true if the given include key was requested.
  """
  @spec included?([atom()], atom()) :: boolean()
  def included?(includes, key), do: key in includes
end
