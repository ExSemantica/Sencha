# Channel state
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
defmodule Sencha.Channel do
  @moduledoc """
  Channel state
  """
  import Ecto.Query

  defstruct [
    :name,
    :topic,
    :topic_changed,
    :topic_changed_by,
    :founder_mask,
    :sticky_modes,
    :created
  ]

  @doc """
  SEE: https://modern.ircdocs.horse/#mode-message
  """
  def modes(?a), do: MapSet.new(~c(bq))
  def modes(?b), do: MapSet.new(~c())
  def modes(?c), do: MapSet.new(~c(ov))
  def modes(?d), do: MapSet.new(~c())

  @doc """
  Gather all user hashes to prepare an operation on all users in the channel
  """
  def gather_hashes(channel) do
    channel_hash = String.downcase(channel)

    :mnesia.transaction(fn ->
      case :mnesia.read(__MODULE__.Roster, channel_hash) do
        [] ->
          []

        [{__MODULE__.Roster, ^channel_hash, targets, _attributes, _modes}] ->
          for target <- targets do
            String.downcase(target.nickname)
          end
      end
    end)
  end

  @doc """
  Do this when a `Sencha.User` JOINs a channel.
  """
  def join(state, socket, channel, target) do
    attributes = attributes_get(channel)
    channel_hash = String.downcase(channel)

    join_stat =
      :mnesia.transaction(fn ->
        case :mnesia.read(__MODULE__.Roster, channel_hash) do
          [] ->
            :mnesia.write(
              {__MODULE__.Roster, channel_hash, [target], attributes, %{?o => [target], ?v => []}}
            )

            {:ok, channel}

          [{__MODULE__.Roster, ^channel_hash, others, attributes, modes}] ->
            if target not in others do
              targets = [target | others]

              for other <- targets do
                other_hash = String.downcase(other.nickname)

                Sencha.User.remote_send(
                  %Sencha.Message{
                    prefix: target,
                    command: "JOIN",
                    middle: [attributes.name]
                  },
                  other_hash
                )
              end

              :mnesia.write(
                {__MODULE__.Roster, channel_hash, [target | others], attributes, modes}
              )

              {:ok, attributes.name}
            else
              :ignore
            end
        end
      end)

    {:atomic, state} =
      case join_stat do
        {:atomic, {:ok, name}} ->
          Sencha.User.Command.handle(state, socket, %Sencha.Message{
            command: "TOPIC",
            middle: [name]
          })

          Sencha.User.Command.handle(state, socket, %Sencha.Message{
            command: "NAMES",
            middle: [name]
          })

          :mnesia.transaction(fn ->
            case :mnesia.read(__MODULE__.Roster, channel_hash) do
              [{__MODULE__.Roster, ^channel_hash, targets, _attributes, modes}] ->
                matchee = Sencha.Prefix.encode(target)
                oper? = modes[?o] |> Enum.any?(&Sencha.Mask.match?(matchee, &1))
                voice? = modes[?v] |> Enum.any?(&Sencha.Mask.match?(matchee, &1))

                cond do
                  oper? ->
                    for t <- targets do
                      Sencha.User.remote_send(
                        %Sencha.Message{
                          prefix: Application.fetch_env!(:sencha, :hostname),
                          command: "MODE",
                          middle: [channel, "+o", matchee.nickname]
                        },
                        String.downcase(t.nickname)
                      )
                    end

                    state

                  voice? ->
                    for t <- targets do
                      Sencha.User.remote_send(
                        %Sencha.Message{
                          prefix: Application.fetch_env!(:sencha, :hostname),
                          command: "MODE",
                          middle: [channel, "+v", matchee.nickname]
                        },
                        String.downcase(t.nickname)
                      )
                    end

                    state

                  true ->
                    state
                end
            end
          end)

        {:atomic, :ignore} ->
          {:atomic, state}
      end

    state
  end

  @doc """
  Do this when a `Sencha.User` PARTs a channel.
  """
  def part(state, socket, channel, target, reason) do
    channel_hash = String.downcase(channel)
  end

  def update_attributes(channel_hash, attributes) do
    # TODO: Notify others!
    :mnesia.transaction(fn ->
      case :mnesia.read(__MODULE__.Roster, channel_hash) do
        [{__MODULE__.Roster, ^channel_hash, targets, _attributes, modes}] ->
          :mnesia.write({__MODULE__.Roster, channel_hash, targets, attributes, modes})
      end
    end)
  end

  def update_modes(channel_hash, modes) do
    # TODO: Notify others!
    :mnesia.transaction(fn ->
      case :mnesia.read(__MODULE__.Roster, channel_hash) do
        [{__MODULE__.Roster, ^channel_hash, targets, attributes, _modes}] ->
          :mnesia.write({__MODULE__.Roster, channel_hash, targets, attributes, modes})
      end
    end)
  end

  def attributes_get(channel) do
    case Sencha.Repo.one(from(c in Sencha.Repo.Channel, where: ilike(^channel, c.name))) do
      nil ->
        %__MODULE__{
          name: channel,
          topic: nil,
          topic_changed: nil,
          topic_changed_by: nil,
          founder_mask: nil,
          sticky_modes: [],
          created: DateTime.utc_now()
        }

      %Sencha.Repo.Channel{
        name: name,
        topic: topic,
        topic_changed: topic_changed,
        topic_changed_by: topic_changed_by,
        founder_mask: founder_mask,
        sticky_modes: sticky_modes,
        inserted_at: created
      } ->
        %__MODULE__{
          name: name,
          topic: topic,
          topic_changed: topic_changed,
          topic_changed_by: topic_changed_by,
          founder_mask: founder_mask,
          sticky_modes: sticky_modes,
          created: created
        }
    end
  end

  @doc """
  Remove a vacant channel from the roster
  """
  def garbage_collect(channel_hash) do
    :mnesia.transaction(fn ->
      case :mnesia.read(__MODULE__.Roster, channel_hash) do
        [{__MODULE__.Roster, ^channel_hash, [], _attributes, _modes}] ->
          :mnesia.delete({__MODULE__.Roster, channel_hash})

        _occupied_or_never_existed ->
          :ok
      end
    end)
  end
end
