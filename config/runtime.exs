import Config

# Helper: read from env var or Docker secret file (VAR_FILE takes precedence)
defmodule Kith.ConfigHelpers do
  def read_secret(env_var) do
    case System.get_env("#{env_var}_FILE") do
      nil -> System.get_env(env_var)
      file_path -> file_path |> String.trim() |> File.read!() |> String.trim()
    end
  end
end

# ## Shared (all environments)

if System.get_env("PHX_SERVER") do
  config :kith, KithWeb.Endpoint, server: true
end

config :kith, KithWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Feature flags
config :kith,
  disable_signup: System.get_env("DISABLE_SIGNUP") == "true",
  signup_double_optin: System.get_env("SIGNUP_DOUBLE_OPTIN", "true") == "true",
  max_upload_size_kb: String.to_integer(System.get_env("MAX_UPLOAD_SIZE_KB", "5120")),
  max_storage_size_mb: String.to_integer(System.get_env("MAX_STORAGE_SIZE_MB", "1024"))

# ## Production-only configuration

if config_env() == :prod do
  database_url =
    Kith.ConfigHelpers.read_secret("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :kith, Kith.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10")),
    ssl: System.get_env("DATABASE_SSL") == "true",
    socket_options: maybe_ipv6

  secret_key_base =
    Kith.ConfigHelpers.read_secret("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("KITH_HOSTNAME") || System.get_env("PHX_HOST") || "localhost"

  config :kith, KithWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base

  config :kith, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Force SSL behind reverse proxy
  config :kith, KithWeb.Endpoint, force_ssl: [rewrite_on: [:x_forwarded_proto]]

  # Email (production)
  config :kith, Kith.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: System.get_env("SMTP_HOST") || raise("SMTP_HOST is required in production"),
    port: String.to_integer(System.get_env("SMTP_PORT", "587")),
    username: System.get_env("SMTP_USERNAME", ""),
    password: Kith.ConfigHelpers.read_secret("SMTP_PASSWORD") || "",
    ssl: System.get_env("SMTP_SSL") == "true",
    tls: :if_available,
    auth: :if_available

  config :kith, Kith.Mailer, from: System.get_env("MAIL_FROM", "noreply@#{host}")

  # S3 storage (optional — falls back to local disk)
  if bucket = System.get_env("AWS_S3_BUCKET") do
    config :ex_aws,
      access_key_id: Kith.ConfigHelpers.read_secret("AWS_ACCESS_KEY_ID"),
      secret_access_key: Kith.ConfigHelpers.read_secret("AWS_SECRET_ACCESS_KEY"),
      region: System.get_env("AWS_REGION", "us-east-1")

    if endpoint = System.get_env("AWS_S3_ENDPOINT") do
      config :ex_aws, :s3,
        scheme: "http://",
        host: URI.parse(endpoint).host,
        port: URI.parse(endpoint).port
    end

    config :kith, Kith.Storage,
      backend: :s3,
      bucket: bucket
  else
    config :kith, Kith.Storage,
      backend: :local,
      path: System.get_env("STORAGE_PATH", "/app/uploads")
  end

  # Rate limiting — optional Redis backend
  if System.get_env("RATE_LIMIT_BACKEND") == "redis" do
    redis_url =
      System.get_env("REDIS_URL") ||
        raise "REDIS_URL is required when RATE_LIMIT_BACKEND=redis"

    config :hammer,
      backend: {Hammer.Backend.Redis, [expiry_ms: 60_000 * 60, redis_url: redis_url]}
  end

  # Sentry error tracking (optional)
  if sentry_dsn = System.get_env("SENTRY_DSN") do
    config :sentry,
      dsn: sentry_dsn,
      environment_name: System.get_env("SENTRY_ENVIRONMENT", "production")
  end

  # Trusted proxies for real IP extraction
  trusted_proxies =
    System.get_env("TRUSTED_PROXIES", "127.0.0.1/8")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)

  config :remote_ip, headers: ~w[x-forwarded-for], proxies: trusted_proxies

  # Structured JSON logging in production
  config :logger, :default_handler,
    formatter: {LoggerJSON.Formatters.Basic, metadata: [:request_id, :user_id, :account_id]}
end
