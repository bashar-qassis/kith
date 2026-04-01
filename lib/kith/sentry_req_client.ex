defmodule Kith.SentryReqClient do
  @moduledoc false
  @behaviour Sentry.HTTPClient

  @impl Sentry.HTTPClient
  def child_spec do
    Supervisor.child_spec({Finch, name: __MODULE__}, id: __MODULE__)
  end

  @impl Sentry.HTTPClient
  def post(url, headers, body) do
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, __MODULE__) do
      {:ok, %Finch.Response{status: status, headers: headers, body: body}} ->
        {:ok, status, headers, body}

      {:error, exception} ->
        {:error, exception}
    end
  end
end
