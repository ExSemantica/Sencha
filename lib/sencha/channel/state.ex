defmodule Sencha.Channel.State do
  @moduledoc """
  Stores state of a `Sencha.Channel`.

  - `:name`: The name of this channel.
  - `:users`: A list of `Sencha.User` processes
  - `:modes`: A map of `Sencha.Channel.Modes`
  - `:topic`: The channel topic
  - `:topic_set`: A `DateTime` saying when the topic was set
  - `:registered?`: A flag saying if this channel has been registered
  - `:owner`: The owner (`Sencha.Repo.User`) ID
  """
  import Ecto.Query

  @enforce_keys ~w(name users modes topic topic_set topic_set_by registered? owner)a

  defstruct [
    :name,
    :users,
    :modes,
    :topic,
    :topic_set,
    :topic_set_by,
    :registered?,
    :owner
  ]

  @doc """
  Convenience for creating new channel states.
  """
  def init(name, joiner) do
    user = Sencha.Repo.one(from(u in Sencha.Repo.User, where: u.nickname == ^joiner))

    channel =
      Sencha.Repo.one(from(c in Sencha.Repo.Channel, where: c.name == ^name, preload: [:user]))

    case channel do
      channel = %Sencha.Repo.Channel{
        name: real_name,
        topic: topic,
        topic_set: topic_set,
        topic_set_by: topic_set_by,
        locked_reason: "",
        user: real_owner
      } ->
        {:ok,
         %__MODULE__{
           name: real_name,
           users: [],
           modes: Sencha.Channel.Modes.to_modemap(channel),
           topic: topic,
           topic_set: topic_set,
           topic_set_by: topic_set_by,
           registered?: true,
           owner: real_owner
         }}

      %Sencha.Repo.Channel{name: real_name, locked_reason: locked_reason} ->
        {:error, {:locked, real_name, locked_reason}}

      nil ->
        {:ok,
         %__MODULE__{
           name: name,
           users: [],
           modes: Sencha.Channel.Modes.defaults(),
           topic: "",
           topic_set: DateTime.utc_now(:second),
           registered?: false,
           owner: user.id,
           topic_set_by: "Services"
         }}
    end
  end

  @doc """
  Convenience for registering a channel to a `Sencha.Repo.User`.
  """
  def register(name, owner = %Sencha.Repo.User{}) do
    {:ok, state} = Sencha.Channel.get_state({:global, {Sencha.Channel, name}})

    if state.registered? do
      :error
    else
      %Sencha.Repo.Channel{
        name: name,
        topic: state.topic,
        topic_set: state.topic_set,
        topic_set_by: state.topic_set_by
      }
      |> Sencha.Channel.Modes.update(state.modes)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:user, owner)
      |> Sencha.Repo.insert()

      Sencha.Channel.mark_registered({:global, {Sencha.Channel, name}}, true)
      Sencha.Channel.mark_owner({:global, {Sencha.Channel, name}}, owner.id)

      :ok
    end
  end
end
