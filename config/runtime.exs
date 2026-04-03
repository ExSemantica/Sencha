import Config

config :sencha,
  host:
    System.get_env("SENCHA_HOST") ||
      raise("""
      environment variable SENCHA_HOST is missing.
      """)

config :sencha, Sencha.Repo,
  url:
    System.get_env("SENCHA_DATABASE") ||
      raise("""
      environment variable SENCHA_DATABASE is missing.
      """)
