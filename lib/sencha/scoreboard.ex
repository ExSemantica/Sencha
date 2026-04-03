defmodule Sencha.Scoreboard do
  @moduledoc """
  Handles counts for 'LUSERS' command

  This requires a Mnesia storage that is globally accessible to all nodes, where
  each server has its own Mnesia table for local storage.
  """
  use GenServer

  # ===========================================================================
  # Public callbacks
  # ===========================================================================
  @doc """
  Starts the scoreboard process for this node only.
  """
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @doc """
  Change this node's total users count
  """
  def change_total(count) do
    GenServer.cast(__MODULE__, {:change_total, count})
  end

  @doc """
  Change this node's invisible users count
  """
  def change_invisible(count) do
    GenServer.cast(__MODULE__, {:change_invisible, count})
  end

  @doc """
  Change this node's IRC operators count
  """
  def change_operators(count) do
    GenServer.cast(__MODULE__, {:change_operators, count})
  end

  @doc """
  Change this node's pending connections count
  """
  def change_unknown(count) do
    GenServer.cast(__MODULE__, {:change_unknown, count})
  end

  @doc """
  Accumulates user counts (currently IRC operator, invisible, and total)
  """
  def accumulate(global?) do
    GenServer.call(__MODULE__, {:accumulate, global?})
  end

  # ===========================================================================
  # Behavioral callbacks
  # ===========================================================================
  @impl GenServer
  def init([]) do
    # We need this to connect ourselves to other Mnesia nodes!
    nodes = Node.list()

    :ok =
      case :mnesia.create_table(Sencha.Scoreboard.Table,
             attributes: ~w(key value)a,
             ram_copies: [node() | nodes],
             disc_copies: [],
             disc_only_copies: []
           ) do
        {:atomic, :ok} ->
          :mnesia.transaction(fn ->
            :mnesia.write({Sencha.Scoreboard.Table, :maximum, 0})
          end)

          :ok

        {:aborted, {:already_exists, Sencha.Scoreboard.Table}} ->
          :mnesia.wait_for_tables([Sencha.Scoreboard.Table], 3_000)
          :ok
      end

    # Canary any scoreboard entry to ensure we actually need a new scoreboard
    :mnesia.transaction(fn ->
      case :mnesia.read(Sencha.Scoreboard.Table, {node(), :total}) do
        [_canary] ->
          :ok

        [] ->
          # Write users total on **this** server
          :mnesia.write({Sencha.Scoreboard.Table, {node(), :total}, 0})

          # Write users maximum on **this** server
          :mnesia.write({Sencha.Scoreboard.Table, {node(), :maximum}, 0})

          # Write users with invisible on **this** server
          :mnesia.write({Sencha.Scoreboard.Table, {node(), :invisible}, 0})

          # Write IRC operators on **this** server
          :mnesia.write({Sencha.Scoreboard.Table, {node(), :operators}, 0})

          # Write pending connections on **this** server
          :mnesia.write({Sencha.Scoreboard.Table, {node(), :unknown}, 0})

          :ok
      end
    end)

    {:ok, []}
  end

  @impl GenServer
  def handle_cast({:change_total, num}, state) do
    # I think the dirty counter updates are lagging behind. Let's try this.
    {:atomic, :ok} =
      :mnesia.transaction(fn ->
        # Store local max
        [{Sencha.Scoreboard.Table, {_node, :maximum}, max_local}] =
          :mnesia.read(Sencha.Scoreboard.Table, {node(), :maximum})

        [{Sencha.Scoreboard.Table, {_node, :total}, total_local}] =
          :mnesia.read(Sencha.Scoreboard.Table, {node(), :total})

        total_local = total_local + num

        if total_local > max_local do
          :mnesia.write({Sencha.Scoreboard.Table, {node(), :maximum}, total_local})
        end

        :mnesia.write({Sencha.Scoreboard.Table, {node(), :total}, total_local})
        :ok
      end)

    {:atomic, :ok} =
      :mnesia.transaction(fn ->
        # Store global max
        total_global =
          :mnesia.foldl(
            fn entry, acc ->
              case entry do
                {Sencha.Scoreboard.Table, {_node, :total}, count} ->
                  acc + count

                _other ->
                  acc
              end
            end,
            0,
            Sencha.Scoreboard.Table,
            :read
          )

        [{Sencha.Scoreboard.Table, :maximum, max_global}] =
          :mnesia.read(Sencha.Scoreboard.Table, :maximum)

        if total_global > max_global do
          :mnesia.write({Sencha.Scoreboard.Table, :maximum, total_global})
        end

        :ok
      end)

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:change_invisible, num}, state) do
    :mnesia.dirty_update_counter({Sencha.Scoreboard.Table, {node(), :invisible}}, num)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:change_operators, num}, state) do
    :mnesia.dirty_update_counter({Sencha.Scoreboard.Table, {node(), :operators}}, num)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:change_unknown, num}, state) do
    :mnesia.dirty_update_counter({Sencha.Scoreboard.Table, {node(), :unknown}}, num)
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:accumulate, global?}, _from, state) do
    {:atomic, sums} =
      :mnesia.transaction(fn ->
        :mnesia.foldl(
          fn entry, acc ->
            case entry do
              # ===============================================================
              # Maximum counts are SEPARATE
              {Sencha.Scoreboard.Table, :maximum, count} ->
                if global? do
                  update_in(acc, [:maximum], &(&1 + count))
                else
                  acc
                end

              {Sencha.Scoreboard.Table, {the_node, :maximum}, count} ->
                if not global? and the_node == node() do
                  update_in(acc, [:maximum], &(&1 + count))
                else
                  acc
                end

              # ===============================================================
              # The other counts are together
              {Sencha.Scoreboard.Table, {the_node, :total}, count} ->
                if global? or the_node == node() do
                  update_in(acc, [:total], &(&1 + count))
                else
                  acc
                end

              {Sencha.Scoreboard.Table, {the_node, :invisible}, count} ->
                if global? or the_node == node() do
                  update_in(acc, [:invisible], &(&1 + count))
                else
                  acc
                end

              {Sencha.Scoreboard.Table, {the_node, :operators}, count} ->
                if global? or the_node == node() do
                  update_in(acc, [:operators], &(&1 + count))
                else
                  acc
                end

              {Sencha.Scoreboard.Table, {the_node, :unknown}, count} ->
                if global? or the_node == node() do
                  update_in(acc, [:unknown], &(&1 + count))
                else
                  acc
                end

              _other ->
                acc
            end
          end,
          %{total: 0, invisible: 0, operators: 0, unknown: 0, maximum: 0},
          Sencha.Scoreboard.Table,
          :read
        )
      end)

    {:reply, {:ok, sums}, state}
  end
end
