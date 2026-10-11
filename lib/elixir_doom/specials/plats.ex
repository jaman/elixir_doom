defmodule ElixirDoom.Specials.Plats do
  @moduledoc """
  Starting lifts and the floors that rise and take another sector's texture, stopping
  them, and starting stopped ones again.

  Kinds: `:down_wait_up_stay` (a lift), `:blaze_dwus`, `:perpetual_raise`,
  `:raise_and_change` (by an amount) and `:raise_to_nearest_and_change`.
  """

  alias ElixirDoom.Specials.{Machines, Sectors}
  alias ElixirDoom.World

  @wait 105

  @doc "Start `type` in every sector tagged by `line` that no mover has taken: `{world, started?}`."
  @spec by_tag(World.t(), map(), atom(), number()) :: {World.t(), boolean()}
  def by_tag(world, line, type, amount) do
    world = if type == :perpetual_raise, do: wake(world, line.tag), else: world

    world
    |> Sectors.tagged(line.tag)
    |> Enum.reject(&Machines.busy?(world, &1))
    |> Enum.reduce({world, false}, fn sector, {acc, _started?} ->
      {start(acc, line, sector, {type, amount}), true}
    end)
  end

  defp start(world, line, index, {type, amount}) do
    sector = World.sector(world, index)
    model = World.sector(world, elem(world.sides, line.front).sector)

    base = %{
      kind: :plat,
      type: type,
      sector: index,
      tag: line.tag,
      crush: false,
      count: 0,
      wait: 0
    }

    {plan, world, sound} = plan(world, index, sector, model, {type, amount})

    world
    |> Machines.start_mover(index, Map.merge(base, plan))
    |> Sectors.sound(index, sound)
  end

  defp plan(world, index, sector, model, {:raise_to_nearest_and_change, _amount}) do
    world =
      World.update_sector(world, index, &%{&1 | floor_picture: model.floor_picture, special: 0})

    high = Sectors.next_highest_floor(world, index, sector.floor)
    {%{speed: 0.5, high: high, low: sector.floor, status: :up}, world, "DSSTNMOV"}
  end

  defp plan(world, index, sector, model, {:raise_and_change, amount}) do
    world = World.update_sector(world, index, &%{&1 | floor_picture: model.floor_picture})

    {%{speed: 0.5, high: sector.floor + amount, low: sector.floor, status: :up}, world,
     "DSSTNMOV"}
  end

  defp plan(world, index, sector, _model, {type, _amount})
       when type in [:down_wait_up_stay, :blaze_dwus] do
    low = min(Sectors.lowest_floor(world, index), sector.floor)
    speed = if type == :blaze_dwus, do: 8.0, else: 4.0
    {%{speed: speed, low: low, high: sector.floor, wait: @wait, status: :down}, world, "DSPSTART"}
  end

  defp plan(world, index, sector, _model, {:perpetual_raise, _amount}) do
    low = min(Sectors.lowest_floor(world, index), sector.floor)
    high = max(Sectors.highest_floor(world, index), sector.floor)
    {roll, world} = World.random(world)
    status = if Bitwise.band(roll, 1) == 1, do: :up, else: :down
    {%{speed: 4.0, low: low, high: high, wait: @wait, status: status}, world, "DSPSTART"}
  end

  @doc "Stop every moving lift tagged `tag` where it is."
  @spec stop(World.t(), integer()) :: World.t()
  def stop(world, tag) do
    Machines.update_where(
      world,
      &match?(%{kind: :plat, tag: ^tag, status: status} when status != :stasis, &1),
      &Map.merge(&1, %{status: :stasis, previous: &1.status})
    )
  end

  defp wake(world, tag) do
    Machines.update_where(
      world,
      &match?(%{kind: :plat, tag: ^tag, status: :stasis}, &1),
      &%{&1 | status: &1.previous}
    )
  end
end
