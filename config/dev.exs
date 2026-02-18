import Config

# Timeouts are in milliseconds
config :sencha, auth_timeout: 15_000
config :sencha, ping_timeout: 15_000
config :sencha, ping_timeout_hard: 5_000

config :sencha, Sencha.Repo,
  adapter: Ecto.Adapters.SQLite3,
  database: "priv/repo/sqlite/sencha.db"

config :sencha, host: "127.0.0.1"
config :sencha, ecto_repos: [Sencha.Repo]
