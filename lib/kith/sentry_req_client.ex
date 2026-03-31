defmodule Kith.SentryReqClient do
  @moduledoc false
  @behaviour Sentry.HTTPClient

  @impl Sentry.HTTPClient
  def post(url, headers, body) do
    case Req.post(url, headers: headers, body: body, decode_body: false, retry: false) do
      {:ok, response} ->
        {:ok, response.status, Enum.to_list(response.headers), response.body}

      {:error, exception} ->
        {:error, exception}
    end
  end
end
