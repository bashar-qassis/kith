import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :pbkdf2_elixir, :rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :kith, Kith.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "kith_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :kith, KithWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "9QVosGIymc5flycbrRXuumAnww6vPwtL7Xf4iOAPW05MoPggLbe8eOQeVT0f8y9R",
  server: false

# Disable Oban in tests (use Oban.Testing)
config :kith, Oban, testing: :inline

# Email — test adapter
config :kith, Kith.Mailer, adapter: Swoosh.Adapters.Test

# Disable Swoosh API client in tests
config :swoosh, :api_client, false

# Disable Sentry in tests
config :sentry, client: Sentry.NoopClient, dsn: nil

# Test metrics token
config :kith, metrics_token: "test-metrics-token"

# Disable email verification by default in tests (override per-test as needed)
config :kith, signup_double_optin: false

# Storage — local backend for tests
config :kith, Kith.Storage, backend: :local, path: "priv/uploads/test"

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
