import Config

if config_env() == :prod do
  chat_hostname =
    System.get_env("CHAT_HOSTNAME") ||
      raise """
      environment CHAT_HOSTNAME is missing.
      Fill it in with your hostname or IP address.
      """

  config :sencha, Sencha.ApplicationInfo,
    chat_hostname: chat_hostname,
    commit_sha_result: :release
end
