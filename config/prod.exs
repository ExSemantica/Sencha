import Config

config :libcluster,
  topologies: [
    exsemantica: [
      strategy: Elixir.Cluster.Strategy.Gossip
    ]
  ]
