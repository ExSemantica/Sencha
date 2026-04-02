defmodule Sencha.MixProject do
  use Mix.Project

  def project do
    [
      app: :sencha,
      version: "0.2.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :mnesia],
      mod: {Sencha.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Keep code clean and organized
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},

      # Create documentation
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},

      # Framework for TCP-based socketing
      {:thousand_island, "~> 1.4"},

      # Handle PostgreSQL database
      {:ecto, "~> 3.13"},
      {:ecto_sql, "~> 3.13"},

      # Authentication provider locally (only for the local SQLite database)
      {:argon2_elixir, "~> 4.1"},

      # Easily implement K-lines
      {:inet_cidr, "~> 1.0"},

      # Operators should use TOTP before doing significant actions
      {:nimble_totp, "~> 1.0"},
      {:eqrcode, "~> 0.2"}

      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
