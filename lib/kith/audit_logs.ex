defmodule Kith.AuditLogs do
  @moduledoc """
  The AuditLogs context — tracks user actions for auditing purposes.

  All audit log writes go through Oban for crash safety. The `log_event/4`
  function enqueues an Oban job rather than inserting directly, so the caller
  is never blocked and entries survive process crashes.
  """

  import Ecto.Query, warn: false
  import Kith.Scope

  alias Kith.Repo
  alias Kith.AuditLogs.AuditLog
  alias Kith.Workers.AuditLogWorker

  @valid_events AuditLog.valid_events()

  ## Listing / Querying

  def list_audit_logs(account_id, filters \\ %{}) do
    limit = parse_limit(filters)
    cursor = Map.get(filters, "cursor") || Map.get(filters, :cursor)

    query =
      AuditLog
      |> scope_to_account(account_id)
      |> order_by([l], [desc: l.inserted_at, desc: l.id])
      |> apply_filters(filters)
      |> apply_cursor(cursor)
      |> limit(^(limit + 1))

    entries = Repo.all(query)
    has_more = length(entries) > limit
    entries = Enum.take(entries, limit)

    next_cursor =
      case List.last(entries) do
        nil -> nil
        last -> encode_cursor(last)
      end

    {entries, %{has_more: has_more, next_cursor: next_cursor}}
  end

  def list_audit_logs_for_contact(account_id, contact_id) do
    AuditLog
    |> scope_to_account(account_id)
    |> where([l], l.contact_id == ^contact_id)
    |> order_by([l], desc: l.inserted_at)
    |> Repo.all()
  end

  ## Writing (synchronous — used by AuditLogWorker)

  def create_audit_log(account_id, attrs) do
    %AuditLog{}
    |> AuditLog.create_changeset(Map.put(attrs, :account_id, account_id))
    |> Repo.insert()
  end

  ## Public API — enqueues async Oban job

  @doc """
  Enqueues an audit log entry via Oban.

  Accepts a user struct (or map with `:id` and `:email`/`:display_name`),
  an event string, and optional keyword opts for `:contact_id`,
  `:contact_name`, and `:metadata`.

  Raises `ArgumentError` if the event is not in the defined set.
  """
  def log_event(account_id, user, event, opts \\ [])

  def log_event(account_id, user, event, opts) when is_atom(event) do
    log_event(account_id, user, Atom.to_string(event), opts)
  end

  def log_event(account_id, user, event, opts) when is_binary(event) do
    unless event in @valid_events do
      raise ArgumentError,
            "unknown audit event #{inspect(event)}. Valid events: #{inspect(@valid_events)}"
    end

    args = %{
      "account_id" => account_id,
      "user_id" => user_id(user),
      "user_name" => user_name(user),
      "event" => event,
      "contact_id" => Keyword.get(opts, :contact_id),
      "contact_name" => Keyword.get(opts, :contact_name),
      "metadata" => Keyword.get(opts, :metadata, %{})
    }

    AuditLogWorker.new(args)
    |> Oban.insert()
  end

  ## Private helpers

  defp user_id(%{id: id}), do: id
  defp user_id(_), do: nil

  defp user_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp user_name(%{email: email}) when is_binary(email), do: email
  defp user_name(_), do: "system"

  defp parse_limit(filters) do
    limit = Map.get(filters, "limit") || Map.get(filters, :limit) || 50
    limit = if is_binary(limit), do: String.to_integer(limit), else: limit
    min(max(limit, 1), 100)
  end

  defp apply_filters(query, filters) do
    query
    |> maybe_filter_event_type(filters)
    |> maybe_filter_contact_name(filters)
    |> maybe_filter_user_name(filters)
    |> maybe_filter_date_from(filters)
    |> maybe_filter_date_to(filters)
  end

  defp maybe_filter_event_type(query, filters) do
    case Map.get(filters, "event_type") || Map.get(filters, :event_type) do
      nil -> query
      "" -> query
      events when is_list(events) -> where(query, [l], l.event in ^events)
      event -> where(query, [l], l.event == ^event)
    end
  end

  defp maybe_filter_contact_name(query, filters) do
    case Map.get(filters, "contact_name") || Map.get(filters, :contact_name) do
      nil -> query
      "" -> query
      name -> where(query, [l], ilike(l.contact_name, ^"%#{name}%"))
    end
  end

  defp maybe_filter_user_name(query, filters) do
    case Map.get(filters, "user_name") || Map.get(filters, :user_name) do
      nil -> query
      "" -> query
      name -> where(query, [l], ilike(l.user_name, ^"%#{name}%"))
    end
  end

  defp maybe_filter_date_from(query, filters) do
    case Map.get(filters, "date_from") || Map.get(filters, :date_from) do
      nil -> query
      "" -> query
      date when is_binary(date) -> where(query, [l], l.inserted_at >= ^parse_date!(date))
      %DateTime{} = dt -> where(query, [l], l.inserted_at >= ^dt)
      %Date{} = d -> where(query, [l], l.inserted_at >= ^DateTime.new!(d, ~T[00:00:00]))
    end
  end

  defp maybe_filter_date_to(query, filters) do
    case Map.get(filters, "date_to") || Map.get(filters, :date_to) do
      nil -> query
      "" -> query
      date when is_binary(date) -> where(query, [l], l.inserted_at <= ^parse_end_of_day!(date))
      %DateTime{} = dt -> where(query, [l], l.inserted_at <= ^dt)
      %Date{} = d -> where(query, [l], l.inserted_at <= ^DateTime.new!(d, ~T[23:59:59]))
    end
  end

  defp parse_date!(date_string) do
    Date.from_iso8601!(date_string) |> DateTime.new!(~T[00:00:00])
  end

  defp parse_end_of_day!(date_string) do
    Date.from_iso8601!(date_string) |> DateTime.new!(~T[23:59:59])
  end

  defp apply_cursor(query, nil), do: query

  defp apply_cursor(query, cursor) do
    case decode_cursor(cursor) do
      {:ok, inserted_at, id} ->
        where(
          query,
          [l],
          l.inserted_at < ^inserted_at or (l.inserted_at == ^inserted_at and l.id < ^id)
        )

      :error ->
        query
    end
  end

  defp encode_cursor(%AuditLog{inserted_at: inserted_at, id: id}) do
    "#{DateTime.to_iso8601(inserted_at)}|#{id}"
    |> Base.url_encode64()
  end

  defp decode_cursor(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor),
         [timestamp_str, id_str] <- String.split(decoded, "|", parts: 2),
         {:ok, timestamp, _} <- DateTime.from_iso8601(timestamp_str),
         {id, ""} <- Integer.parse(id_str) do
      {:ok, timestamp, id}
    else
      _ -> :error
    end
  end
end
