import Config

config :sencha,
  host:
    System.get_env("SENCHA_HOST") ||
      raise("""
      environment variable SENCHA_HOST is missing.
      """)
