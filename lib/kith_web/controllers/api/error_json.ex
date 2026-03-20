defmodule KithWeb.API.ErrorJSON do
  @moduledoc """
  Renders all API errors as RFC 7807 Problem Details JSON.

  Content-Type for errors: `application/problem+json`.

  See: https://datatracker.ietf.org/doc/html/rfc7807
  """

  @doc """
  Renders a generic RFC 7807 error from a status code and detail message.
  """
  def render(status, detail, instance \\ nil) do
    %{
      type: "about:blank",
      title: title_for(status),
      status: status,
      detail: detail
    }
    |> maybe_put(:instance, instance)
  end

  @doc """
  Renders a 422 changeset error with field-level errors.
  """
  def changeset_error(%Ecto.Changeset{} = changeset, instance \\ nil) do
    %{
      type: "about:blank",
      title: "Unprocessable Entity",
      status: 422,
      detail: "Validation failed.",
      errors: traverse_errors(changeset)
    }
    |> maybe_put(:instance, instance)
  end

  defp traverse_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp title_for(400), do: "Bad Request"
  defp title_for(401), do: "Unauthorized"
  defp title_for(403), do: "Forbidden"
  defp title_for(404), do: "Not Found"
  defp title_for(409), do: "Conflict"
  defp title_for(422), do: "Unprocessable Entity"
  defp title_for(429), do: "Too Many Requests"
  defp title_for(500), do: "Internal Server Error"
  defp title_for(501), do: "Not Implemented"
  defp title_for(_), do: "Error"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
