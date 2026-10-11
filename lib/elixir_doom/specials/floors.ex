defmodule ElixirDoom.Specials.Floors do
  @moduledoc """
  Starting floors that move by tag, and stairs that build themselves step by step.

  Floor kinds: `:lower` (to the highest floor round it), `:lower_to_lowest`,
  `:turbo_lower`, `:raise` (to the lowest ceiling round it), `:raise_crush`,
  `:raise_to_nearest`, `:raise_24`, `:raise_24_change`, `:raise_to_texture` and
  `:lower_and_change`. Stair kinds: `:build8` and `:turbo16`.
  """

  alias Cauldron2D.Sectors.Map, as: SectorMap
  alias ElixirDoom.Specials.{Machines, Sectors}
  alias ElixirDoom.World

  @doc """
  Start floor `type` in every sector tagged by `line` that no mover has taken:
  `{world, started?}`. `line` is a level line, whose front sector lends its floor to the
  kinds that change texture, or `%{tag: tag}` alone.
  """
  @spec by_tag(World.t(), map(), atom()) :: {World.t(), boolean()}
  def by_tag(world, line, type) do
    world
    |> Sectors.tagged(line.tag)
    |> Enum.reject(&Machines.busy?(world, &1))
    |> Enum.reduce({world, false}, fn sector, {acc, _started?} ->
      {Machines.start_mover(acc, sector, mover(acc, line, sector, type)), true}
    end)
  end

  defp mover(world, line, index, type) do
    sector = World.sector(world, index)
    base = %{kind: :floor, type: type, sector: index, crush: false, speed: 1.0, change: nil}
    Map.merge(base, plan(world, line, index, sector, type))
  end

  defp plan(world, _line, index, _sector, :lower),
    do: %{direction: -1, destination: Sectors.highest_floor(world, index)}

  defp plan(world, _line, index, _sector, :lower_to_lowest),
    do: %{direction: -1, destination: Sectors.lowest_floor(world, index)}

  defp plan(world, _line, index, sector, :turbo_lower) do
    destination = Sectors.highest_floor(world, index)
    destination = if destination != sector.floor, do: destination + 8, else: destination
    %{direction: -1, speed: 4.0, destination: destination}
  end

  defp plan(world, _line, index, sector, :raise),
    do: %{direction: 1, destination: min(Sectors.lowest_ceiling(world, index), sector.ceiling)}

  defp plan(world, _line, index, sector, :raise_crush),
    do: %{
      direction: 1,
      crush: true,
      destination: min(Sectors.lowest_ceiling(world, index), sector.ceiling) - 8
    }

  defp plan(world, _line, index, sector, :raise_to_nearest),
    do: %{direction: 1, destination: Sectors.next_highest_floor(world, index, sector.floor)}

  defp plan(_world, _line, _index, sector, :raise_24),
    do: %{direction: 1, destination: sector.floor + 24}

  defp plan(world, line, _index, sector, :raise_24_change),
    do: %{direction: 1, destination: sector.floor + 24, change: front_change(world, line)}

  defp plan(world, _line, index, sector, :raise_to_texture),
    do: %{direction: 1, destination: sector.floor + Sectors.shortest_lower(world, index)}

  defp plan(world, _line, index, _sector, :lower_and_change) do
    destination = Sectors.lowest_floor(world, index)

    change =
      case Enum.find(Sectors.neighbours(world, index), &(&1.floor == destination)) do
        nil -> nil
        model -> %{floor_picture: model.floor_picture, special: model.special}
      end

    %{direction: -1, destination: destination, change: change}
  end

  defp front_change(world, %{front: front}) when is_integer(front) do
    model = World.sector(world, elem(world.sides, front).sector)
    %{floor_picture: model.floor_picture, special: model.special}
  end

  defp front_change(_world, _line), do: nil

  @doc "Build stairs of `type` from every sector tagged `tag`: `{world, started?}`."
  @spec stairs(World.t(), integer(), :build8 | :turbo16) :: {World.t(), boolean()}
  def stairs(world, tag, type) do
    {speed, size} = if type == :turbo16, do: {4.0, 16.0}, else: {0.25, 8.0}

    world
    |> Sectors.tagged(tag)
    |> Enum.reject(&Machines.busy?(world, &1))
    |> Enum.reduce({world, false}, fn sector, {acc, _started?} ->
      first = World.sector(acc, sector)
      {climb(acc, sector, first.floor_picture, {first.floor + size, speed, size}), true}
    end)
  end

  defp climb(world, sector, texture, {height, speed, size}) do
    world =
      Machines.start_mover(world, sector, %{
        kind: :floor,
        type: :stairs,
        sector: sector,
        crush: false,
        speed: speed,
        direction: 1,
        destination: height,
        change: nil
      })

    case next_step(world, sector, texture) do
      nil -> world
      next -> climb(world, next, texture, {height + size, speed, size})
    end
  end

  defp next_step(world, sector, texture) do
    world.noise
    |> Map.get(sector, [])
    |> Enum.filter(&(SectorMap.side_sector(world.map, &1, 0) == sector))
    |> Enum.map(&SectorMap.side_sector(world.map, &1, 1))
    |> Enum.find(
      &(World.sector(world, &1).floor_picture == texture and not Machines.busy?(world, &1))
    )
  end
end
