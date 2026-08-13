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
  require Logger
  import Ecto.Query

  defstruct [
    :name,
    :topic,
    :topic_changed,
    :topic_changed_by,
    :sticky_modes,
    :created
  ]

  @doc """
  SEE: https://modern.ircdocs.horse/#mode-message
  """
  def modes(?a), do: MapSet.new(~c(be))
  def modes(?b), do: MapSet.new(~c())
  def modes(?c), do: MapSet.new(~c(OVov))
  def modes(?d), do: MapSet.new(~c(nt))

  @doc """
  Gather all user hashes to prepare an operation on all users in the channel
  """
  def gather_hashes(channel) do
    channel_hash = String.downcase(channel)

    {:atomic, return} =
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

    return
  end

  @doc """
  Do not call this, it is an intermediate stage for `Sencha.User.remote_chghost`
  """
  def legacy_chghost(channel_hash, new_target) do
    {:atomic, what} =
      :mnesia.transaction(fn ->
        case :mnesia.read(__MODULE__.Roster, channel_hash) do
          [
            {__MODULE__.Roster, ^channel_hash, _others, attributes = %__MODULE__{name: name},
             modes}
          ] ->
            [
              %Sencha.Message{
                prefix: new_target |> Sencha.Prefix.encode(),
                command: "JOIN",
                middle: [name]
              },
              bake_modes(attributes, modes, new_target)
            ]

          [] ->
            nil
        end
      end)

    what
  end

  @doc """
  Do this when a `Sencha.User` JOINs a channel.
  """
  def join(state = %Sencha.User{channel_hashes: channel_hashes}, socket, channel, target) do
    attributes = attributes_get(channel)
    channel_hash = String.downcase(channel)

    join_stat =
      :mnesia.transaction(fn ->
        case :mnesia.read(__MODULE__.Roster, channel_hash) do
          [] ->
            :mnesia.write(
              {__MODULE__.Roster, channel_hash, [target], attributes,
               %{?o => [target], ?v => [], ?b => [], ?e => [], ?n => nil, ?t => nil}}
            )

            :ok

          [
            {__MODULE__.Roster, ^channel_hash, others, attributes = %__MODULE__{name: real_name},
             modes = %{?b => bans, ?e => exempts}}
          ] ->
            origin = target |> Sencha.Prefix.encode()

            banned? =
              for ban <- bans do
                Sencha.Prefix.match?(ban, origin)
              end
              |> Enum.any?()

            exempt? =
              for exempt <- exempts do
                Sencha.Prefix.match?(exempt, origin)
              end
              |> Enum.any?()

            cond do
              banned? and not exempt? ->
                # User is banned, do NOT let them join
                Sencha.User.message_send(
                  socket,
                  Sencha.User.Numeric.encode(:ERR_BANNEDFROMCHAN, target, %{
                    channel: real_name
                  }),
                  target
                )

                :ignore

              target not in others ->
                :mnesia.write(
                  {__MODULE__.Roster, channel_hash, [target | others], attributes, modes}
                )

                :ok

              true ->
                :ignore
            end
        end
      end)

    case join_stat do
      {:atomic, :ok} ->
        :mnesia.transaction(fn ->
          case :mnesia.read(__MODULE__.Roster, channel_hash) do
            [
              {__MODULE__.Roster, ^channel_hash, targets, %__MODULE__{name: name, topic: topic},
               modes}
            ] ->
              origin = target |> Sencha.Prefix.encode()

              for other <- targets, other != target do
                other_hash = String.downcase(other.nickname)

                Sencha.User.remote_send(
                  %Sencha.Message{
                    prefix: origin,
                    command: "JOIN",
                    middle: [name]
                  },
                  other_hash
                )
              end

              Sencha.User.message_send(
                socket,
                %Sencha.Message{
                  prefix: origin,
                  command: "JOIN",
                  middle: [name]
                },
                target
              )

              mode_notify = bake_modes(attributes, modes, target)

              if not is_nil(mode_notify) do
                Sencha.User.message_send(
                  socket,
                  mode_notify,
                  target
                )

                for other <- targets, other != target do
                  Sencha.User.remote_send(mode_notify, String.downcase(other.nickname))
                end
              end

              Sencha.User.Command.handle(state, socket, %Sencha.Message{
                command: "MODE",
                middle: [name]
              })

              if not is_nil(topic) do
                Sencha.User.Command.handle(state, socket, %Sencha.Message{
                  command: "TOPIC",
                  middle: [name]
                })
              end

              Sencha.User.Command.handle(state, socket, %Sencha.Message{
                command: "NAMES",
                middle: [name]
              })
          end
        end)

        %Sencha.User{state | channel_hashes: [channel_hash | channel_hashes]}

      {:atomic, :ignore} ->
        state
    end
  end

  @doc """
  Do this when a `Sencha.User` PARTs a channel.
  """
  def part(state = %Sencha.User{channel_hashes: channel_hashes}, socket, channel, target, reason) do
    channel_hash = String.downcase(channel)

    {:atomic, state} =
      :mnesia.transaction(fn ->
        case :mnesia.read(__MODULE__.Roster, channel_hash) do
          [] ->
            state

          [
            {__MODULE__.Roster, ^channel_hash, targets, attributes = %__MODULE__{name: real_name},
             modes}
          ] ->
            origin = target |> Sencha.Prefix.encode()

            if target in targets do
              for t <- targets do
                Sencha.User.remote_send(
                  %Sencha.Message{
                    prefix: origin,
                    command: "PART",
                    middle: [real_name],
                    trailing: reason
                  },
                  String.downcase(t.nickname)
                )
              end

              :mnesia.write(
                {__MODULE__.Roster, channel_hash, targets |> List.delete(target), attributes,
                 modes}
              )

              garbage_collect(channel_hash)

              %Sencha.User{state | channel_hashes: channel_hashes |> List.delete(channel_hash)}
            else
              Sencha.User.message_send(
                socket,
                Sencha.User.Numeric.encode(:ERR_NOTONCHANNEL, target, %{
                  channel: real_name
                }),
                target
              )

              state
            end
        end
      end)

    state
  end

  @doc """
  Change a target, either nickname or hostmask
  """
  def nick(channel_hash, old_target, new_target) do
    :mnesia.transaction(fn ->
      case :mnesia.read(__MODULE__.Roster, channel_hash) do
        [
          {__MODULE__.Roster, ^channel_hash, targets, attributes = %__MODULE__{name: real_name},
           modes}
        ] ->
          old = old_target |> Sencha.Prefix.encode()

          for t <- targets do
            Sencha.User.remote_send(
              %Sencha.Message{
                prefix: old,
                command: "NICK",
                middle: [real_name, new_target.nickname]
              },
              String.downcase(t.nickname)
            )
          end

          :mnesia.write(
            {__MODULE__.Roster, channel_hash, [new_target | targets |> List.delete(old_target)],
             attributes, modes}
          )
      end
    end)
  end

  @doc """
  KICK a user

  - "origin" can be a string or a `Sencha.Prefix`
  - "kick_target" must be a `Sencha.Prefix`
  """
  def kick(channel_hash, origin, kick_target, reason) do
    :mnesia.transaction(fn ->
      case :mnesia.read(__MODULE__.Roster, channel_hash) do
        [
          {__MODULE__.Roster, ^channel_hash, targets, attributes = %__MODULE__{name: real_name},
           modes}
        ]
        when not is_map(origin) ->
          for t <- targets do
            Sencha.User.remote_send(
              %Sencha.Message{
                prefix: origin,
                command: "KICK",
                middle: [real_name, kick_target.nickname],
                trailing: reason
              },
              String.downcase(t.nickname)
            )
          end

          :mnesia.write(
            {__MODULE__.Roster, channel_hash, targets |> List.delete(kick_target), attributes,
             modes}
          )
      end
    end)
  end

  @doc """
  Updates the channel topic given a `Sencha.Prefix`
  """
  def update_topic(channel_hash, topic, origin) do
    :mnesia.transaction(fn ->
      case :mnesia.read(__MODULE__.Roster, channel_hash) do
        [
          {__MODULE__.Roster, ^channel_hash, targets, attributes = %__MODULE__{name: real_name},
           modes}
        ] ->
          :mnesia.write(
            {__MODULE__.Roster, channel_hash, targets,
             %__MODULE__{
               attributes
               | topic: topic,
                 topic_changed_by: origin.nickname,
                 topic_changed: DateTime.utc_now()
             }, modes}
          )

          updater = origin |> Sencha.Prefix.encode()

          for t <- targets do
            Sencha.User.remote_send(
              %Sencha.Message{
                prefix: updater,
                command: "TOPIC",
                middle: [real_name],
                trailing: topic
              },
              String.downcase(t.nickname)
            )
          end
      end
    end)
  end

  @doc """
  Updates the channel modes given a `Sencha.Prefix`
  """
  def update_modes_in_transaction(channel_hash, origin, mode_delta, add_or_del) do
    mode_prefix =
      case add_or_del do
        :add -> "+"
        :del -> "-"
      end

    mode_key = mode_delta |> Enum.map_join(fn {k, v} -> String.duplicate(k, length(v)) end)
    mode_val = mode_delta |> Map.reject(fn {_, v} -> is_nil(v) end) |> Map.values()

    case :mnesia.read(__MODULE__.Roster, channel_hash) do
      [
        {__MODULE__.Roster, ^channel_hash, targets, attributes = %__MODULE__{name: real_name},
         old_modes}
      ] ->
        new_modes =
          case add_or_del do
            :add ->
              mode_delta
              |> Enum.reduce(old_modes, fn {k, v}, acc ->
                old = acc[k]
                have_param? = ?a..?c |> Enum.any?(fn t -> MapSet.member?(modes(t), k) end)
                no_param? = MapSet.member?(modes(?d), k)

                cond do
                  is_nil(v) and no_param? ->
                    # the mode only takes a key, not a value
                    acc |> put_in([k], nil)

                  have_param? ->
                    # the mode takes a key and a value
                    acc |> put_in([k], [v | old])

                  true ->
                    # the mode doesn't exist
                    acc
                end
              end)

            :del ->
              mode_delta
              |> Enum.reduce(old_modes, fn {k, v}, acc ->
                old = acc[k]
                # The conventions here differ when removing channel modes
                # SEE: https://modern.ircdocs.horse/#channel-mode
                have_param? = ?a..?b |> Enum.any?(fn t -> MapSet.member?(modes(t), k) end)
                no_param? = ?c..?d |> Enum.any?(fn t -> MapSet.member?(modes(t), k) end)

                cond do
                  is_nil(acc[k]) and no_param? ->
                    # the mode only takes a key, not a value
                    acc |> pop_in([k])

                  have_param? ->
                    # the mode takes a key and a value
                    acc |> put_in([k], List.delete(v, old))

                  true ->
                    # the mode doesn't exist
                    acc
                end
              end)
          end

        :mnesia.write({__MODULE__.Roster, channel_hash, targets, attributes, new_modes})
        updater = origin |> Sencha.Prefix.encode()

        for t <- targets do
          Sencha.User.remote_send(
            %Sencha.Message{
              prefix: updater,
              command: "MODE",
              middle: [real_name, mode_prefix <> mode_key | mode_val]
            },
            String.downcase(t.nickname)
          )
        end
    end
  end

  def attributes_get(channel) do
    case Sencha.Repo.one(from(c in Sencha.Repo.Channel, where: ilike(^channel, c.name))) do
      nil ->
        %__MODULE__{
          name: channel,
          topic: nil,
          topic_changed: nil,
          topic_changed_by: nil,
          sticky_modes: [],
          created: DateTime.utc_now()
        }

      %Sencha.Repo.Channel{
        name: name,
        topic: topic,
        topic_changed: topic_changed,
        topic_changed_by: topic_changed_by,
        sticky_modes: sticky_modes,
        inserted_at: created
      } ->
        %__MODULE__{
          name: name,
          topic: topic,
          topic_changed: topic_changed,
          topic_changed_by: topic_changed_by,
          sticky_modes: sticky_modes,
          created: created
        }
    end
  end

  @doc """
  Remove a vacant channel from the roster
  """
  def garbage_collect(channel_hash) do
    Logger.debug(channel_hash)

    :mnesia.transaction(fn ->
      case :mnesia.read(__MODULE__.Roster, channel_hash) do
        [{__MODULE__.Roster, ^channel_hash, [], _attributes, _modes}] ->
          :mnesia.delete({__MODULE__.Roster, channel_hash})

        _occupied_or_never_existed ->
          :ok
      end
    end)
  end

  def try_broadcast(
        {Sencha.Channel.Roster, _channel_hash, targets, %Sencha.Channel{name: real_channel},
         modes},
        target,
        on_success,
        error_handlers
      ) do
    matchee = target |> Sencha.Prefix.encode()

    banned? =
      modes[?b]
      |> Enum.any?(&Sencha.Mask.match?(matchee, &1 |> Sencha.Prefix.encode()))

    exception? =
      modes[?e]
      |> Enum.any?(&Sencha.Mask.match?(matchee, &1 |> Sencha.Prefix.encode()))

    cond do
      banned? and not exception? ->
        # Silently fail if this user is banned
        :ok

      Map.has_key?(modes, ?n) and target not in targets ->
        error_handler = error_handlers[:on_not_in_channel] || fn -> nil end
        error_handler.()

      true ->
        origin = target |> Sencha.Prefix.encode()
        recipients = targets |> List.delete(target)

        for r <- recipients do
          on_success.(real_channel, origin, r)
        end
    end
  end

  def bake_modes(%__MODULE__{name: name}, modes, target) do
    matchee = Sencha.Prefix.encode(target)

    mode_prebake =
      %{
        ?o =>
          modes[?o]
          |> Enum.any?(&Sencha.Mask.match?(matchee, &1 |> Sencha.Prefix.encode())),
        ?v =>
          modes[?v]
          |> Enum.any?(&Sencha.Mask.match?(matchee, &1 |> Sencha.Prefix.encode()))
      }

    mode_key =
      mode_prebake
      |> Enum.reduce(nil, fn {k, v}, acc ->
        cond do
          v and is_nil(acc) ->
            [?+, k]

          v ->
            [k | acc]

          true ->
            acc
        end
      end)

    if is_nil(mode_key) do
      nil
    else
      mode_key = IO.inspect(
        mode_key |> to_string())

      mode_val = matchee |> List.duplicate(map_size(mode_prebake))

      %Sencha.Message{
        prefix: Application.fetch_env!(:sencha, :hostname),
        command: "MODE",
        middle:
          IO.inspect([
            [name, mode_key]
            | mode_val
          ] |> List.flatten())
      }
    end
  end
end
