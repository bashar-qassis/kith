defmodule KithWeb.API.Pagination do
  @moduledoc """
  Cursor-based pagination for API list endpoints.

  Cursors are opaque base64-encoded JSON containing the last record's ID.
  Clients must not parse or construct cursors — they are passed through as-is.

  ## Usage

      import KithWeb.API.Pagination

      def index(conn, params) do
        {contacts, meta} =
          Contact
          |> scope_active(account_id)
          |> paginate(params)

        json(conn, %{data: render_contacts(contacts), meta: meta})
      end
  """

  import Ecto.Query
  alias Kith.Repo

  @default_limit 20
  @max_limit 100

  @doc """
  Paginates a query using cursor-based pagination.

  Accepts params with optional `"after"` cursor and `"limit"` page size.
  Returns `{results, meta}` where meta contains `next_cursor` and `has_more`.
  """
  @spec paginate(Ecto.Queryable.t(), map()) :: {list(), map()}
  def paginate(query, params) do
    limit = parse_limit(params)

    query =
      case decode_cursor(params["after"]) do
        {:ok, last_id} ->
          from(q in query, where: q.id > ^last_id)

        :start ->
          query
      end

    results =
      query
      |> order_by([q], asc: q.id)
      |> limit(^(limit + 1))
      |> Repo.all()

    has_more = length(results) > limit
    page = if has_more, do: Enum.take(results, limit), else: results

    next_cursor =
      if has_more do
        page |> List.last() |> encode_cursor()
      end

    {page, %{next_cursor: next_cursor, has_more: has_more}}
  end

  @doc """
  Wraps data and meta into the standard paginated response envelope.
  """
  def paginated_response(data, meta) do
    %{data: data, meta: meta}
  end

  defp parse_limit(params) do
    case params["limit"] do
      nil -> @default_limit
      val when is_binary(val) -> val |> String.to_integer() |> clamp_limit()
      val when is_integer(val) -> clamp_limit(val)
      _ -> @default_limit
    end
  rescue
    ArgumentError -> @default_limit
  end

  defp clamp_limit(n) when n < 1, do: @default_limit
  defp clamp_limit(n) when n > @max_limit, do: @max_limit
  defp clamp_limit(n), do: n

  @doc """
  Decodes a cursor string. Returns `{:ok, id}` or `:start` for nil/empty cursors.
  Returns `{:error, :invalid_cursor}` for malformed cursors.
  """
  def decode_cursor(nil), do: :start
  def decode_cursor(""), do: :start

  def decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, %{"id" => id}} when is_integer(id) <- Jason.decode(json) do
      {:ok, id}
    else
      _ -> {:error, :invalid_cursor}
    end
  end

  defp encode_cursor(%{id: id}) do
    %{"id" => id}
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end
end
