import Config

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Commit SHA for Git, displayed in ircd
# Also define a hostname
commit_sha_result = System.cmd("git", ["rev-parse", "--short", "HEAD"])

config :sencha, Sencha.ApplicationInfo,
  commit_sha_result: commit_sha_result,
  chat_hostname: "127.0.0.1"
