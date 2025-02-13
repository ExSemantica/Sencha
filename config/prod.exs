import Config

# Do not print debug messages in production
config :logger, level: :info

config :libcluster,
  topologies: [
    exsemantica: [
      strategy: Elixir.Cluster.Strategy.Gossip
    ]
  ]
