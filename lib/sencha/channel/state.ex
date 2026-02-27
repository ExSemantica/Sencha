defmodule Sencha.Channel.State do
  @moduledoc """
  Stores state of a `Sencha.Channel`.

  - `:users`: A list of `Sencha.User` processes.
  """
  @enforce_keys ~w(users)a

  defstruct [
    :users
  ]
end
