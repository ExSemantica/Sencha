defmodule Sencha.MixProject do
  use Mix.Project

  def project do
    [
      app: :sencha,
      version: "0.11.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Sencha.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Keep code clean and organized
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},

      # Create documentation for Sencha
      {:ex_doc, "~> 0.35", only: :dev, runtime: false},

      # Framework for TCP-based chat
      {:thousand_island, "~> 1.3"},

      # For joining to the ExSemantica main node in order to get user info
      {:libcluster, "~> 3.5"}
    ]
  end
end
