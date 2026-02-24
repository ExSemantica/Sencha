import Config

config :sencha, ecto_repos: [Sencha.Repo]
config :sencha, Sencha.Repo,
  adapter: Ecto.Adapters.SQLite3,
  database: "data/sencha_test.db"
