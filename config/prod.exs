import Config

# Timeouts are in milliseconds
config :sencha, auth_timeout: 15_000
config :sencha, ping_timeout: 120_000
config :sencha, ping_timeout_hard: 5_000

# These are in seconds
config :sencha, oper_duration: 30

config :sencha, Sencha.Repo,
  adapter: Ecto.Adapters.SQLite3,
  database: "data/sencha.db"

config :mnesia, dir: ~c"data/sencha_#{node()}"

config :sencha, ecto_repos: [Sencha.Repo]
