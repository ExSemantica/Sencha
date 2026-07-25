# Elixir Mixfile
# Copyright 2026 Roland Metivier
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Sencha.MixProject do
  use Mix.Project

  def project do
    [
      app: :sencha,
      version: "0.4.0",
      elixir: "~> 1.20",
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
      # PostgreSQL support
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.22"},
      # TCP socket support
      {:thousand_island, "~> 1.5"},
      # K-Lines are CIDR-based
      {:inet_cidr, "~> 1.0"},
      # Parse hostmasks
      {:nimble_parsec, "~> 1.4"},
      # Hash passwords
      {:argon2_elixir, "~> 4.1"},
      # Unicode unmangling for name/channel suggestions
      {:unidecode, "~> 1.0"},

      # Code cleanliness, etc.
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false, warn_if_outdated: true},
      # Test IRCv3 message cases
      {:yaml_elixir, "~> 2.12", only: [:test]}
    ]
  end
end
