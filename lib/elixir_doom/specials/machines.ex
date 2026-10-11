defmodule ElixirDoom.Specials.Machines do
  @moduledoc """
  The world's running machines — movers, lights, switch timers — kept as
  `Cauldron2D.Thinkers`, and which sectors a mover has taken. A sector taken by one mover
  is not given to another until the first is released.
  """

  alias Cauldron2D.Thinkers
  alias ElixirDoom.World

  @doc "Start `thinker`."
  @spec start(World.t(), map()) :: World.t()
  def start(world, thinker) do
    {_id, thinkers} = Thinkers.add(world.thinkers, thinker)
    %{world | thinkers: thinkers}
  end

  @doc "Start `mover` on `sector`, taking the sector."
  @spec start_mover(World.t(), non_neg_integer(), map()) :: World.t()
  def start_mover(world, sector, mover) do
    {id, thinkers} = Thinkers.add(world.thinkers, mover)
    %{world | thinkers: thinkers, busy: Map.put(world.busy, sector, id)}
  end

  @doc "Whether a mover has taken `sector`."
  @spec busy?(World.t(), non_neg_integer()) :: boolean()
  def busy?(world, sector), do: Map.has_key?(world.busy, sector)

  @doc "The mover on `sector`, as `{id, mover}`, or `nil`."
  @spec mover(World.t(), non_neg_integer()) :: {pos_integer(), map()} | nil
  def mover(world, sector) do
    with id when id != nil <- Map.get(world.busy, sector),
         %{} = mover <- Thinkers.get(world.thinkers, id) do
      {id, mover}
    end
  end

  @doc "Give `sector` back once its mover has stopped."
  @spec release(World.t(), non_neg_integer()) :: World.t()
  def release(world, sector), do: %{world | busy: Map.delete(world.busy, sector)}

  @doc "Replace thinker `id` with `fun.(thinker)`."
  @spec update(World.t(), pos_integer(), (map() -> map())) :: World.t()
  def update(world, id, fun), do: %{world | thinkers: Thinkers.update(world.thinkers, id, fun)}

  @doc "Apply `fun` to every thinker `match?` accepts."
  @spec update_where(World.t(), (map() -> boolean()), (map() -> map())) :: World.t()
  def update_where(world, match?, fun) do
    world.thinkers
    |> Thinkers.to_list()
    |> Enum.filter(fn {_id, thinker} -> match?.(thinker) end)
    |> Enum.reduce(world, fn {id, _thinker}, acc -> update(acc, id, fun) end)
  end
end
