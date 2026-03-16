import Config

# Timeouts are in milliseconds
config :sencha, auth_timeout: 15_000
config :sencha, ping_timeout: 60_000
config :sencha, ping_timeout_hard: 5_000

# These are in seconds
config :sencha, oper_duration: 30

config :sencha, Sencha.Repo,
  adapter: Ecto.Adapters.SQLite3,
  database: "data/sencha_dev.db"

config :mnesia, dir: ~c"data/sencha_dev_#{node()}"

config :sencha, ecto_repos: [Sencha.Repo]
