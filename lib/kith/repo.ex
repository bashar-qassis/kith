defmodule Kith.Repo do
  use Ecto.Repo,
    otp_app: :kith,
    adapter: Ecto.Adapters.Postgres
end
