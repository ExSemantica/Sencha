defmodule Sencha.UserPool do
  @moduledoc """
  Stores all users for easy iteration.
  """
  use Agent

  @doc """
  Starts the user pool.
  """
  def start_link([]) do
    Agent.start_link(fn -> MapSet.new() end, name: __MODULE__)
  end

  @doc """
  Inserts a username into the pool.
  """
  def insert(user) do
    Agent.update(__MODULE__, & MapSet.put(&1, user))
  end

  @doc """
  Deletes a username from the pool.
  """
  def delete(user) do
    Agent.update(__MODULE__, & MapSet.delete(&1, user))
  end

  @doc """
  Checks if a user is in the pool.
  """
  def member?(user) do
    Agent.get(__MODULE__, & MapSet.member?(&1, user))
  end

  @doc """
  Returns the pool members.
  """
  def all() do
    Agent.get(__MODULE__, & &1)
  end
end
