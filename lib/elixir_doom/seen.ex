defmodule ElixirDoom.Seen do
  @moduledoc """
  The lines each player has seen on each level, for their automap. The view that draws a
  player's picture records what it drew; the automap reads it back.

      ElixirDoom.Seen.add({"alice", "E1M1"}, lines)
      ElixirDoom.Seen.get({"alice", "E1M1"})

  Kept in a public ETS table created by `ElixirDoom.Application`.
  """

  @table __MODULE__

  @doc "Create the table. Called once by the application."
  @spec create() :: :ok
  def create do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    :ok
  end

  @doc "Add `lines` to what `key` has seen."
  @spec add(term(), MapSet.t()) :: :ok
  def add(key, lines) do
    :ets.insert(@table, {key, MapSet.union(get(key), lines)})
    :ok
  end

  @doc "What `key` has seen."
  @spec get(term()) :: MapSet.t()
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, lines}] -> lines
      [] -> MapSet.new()
    end
  end
end
