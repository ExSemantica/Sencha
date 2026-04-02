import Config

config :sencha,
  host:
    System.get_env("SENCHA_HOST") ||
      raise("""
      environment variable SENCHA_HOST is missing.
      """)

config :sencha, Sencha.Repo,
  adapter: Ecto.Adapters.Postgres,
  database:
    System.get_env("SENCHA_POSTGRES_URI") ||
      raise("""
      environment variable SENCHA_POSTGRES_URI is missing.
      """)
