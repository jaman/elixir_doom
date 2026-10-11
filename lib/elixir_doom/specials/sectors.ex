defmodule ElixirDoom.Specials.Sectors do
  @moduledoc """
  Questions the level's machinery asks about sectors: their neighbours' floors,
  ceilings and lights, which sectors carry a tag, where a sector is, and the shortest
  lower texture round one.
  """

  alias Cauldron2D.Sectors.Map, as: SectorMap
  alias Cauldron2D.Sectors.Pictures
  alias ElixirDoom.{Assets, World}

  @doc "The sectors sharing a two-sided line with sector `index`, as they are now."
  @spec neighbours(World.t(), non_neg_integer()) :: [map()]
  def neighbours(world, index) do
    world.noise
    |> Map.get(index, [])
    |> Enum.flat_map(fn line ->
      [SectorMap.side_sector(world.map, line, 0), SectorMap.side_sector(world.map, line, 1)]
    end)
    |> Enum.reject(&(&1 == index))
    |> Enum.uniq()
    |> Enum.map(&World.sector(world, &1))
  end

  @doc "The lowest ceiling round sector `index`, or its own where it has no neighbours."
  @spec lowest_ceiling(World.t(), non_neg_integer()) :: float()
  def lowest_ceiling(world, index), do: extreme(world, index, :ceiling, &Enum.min/1)

  @doc "The highest ceiling round sector `index`, or its own."
  @spec highest_ceiling(World.t(), non_neg_integer()) :: float()
  def highest_ceiling(world, index), do: extreme(world, index, :ceiling, &Enum.max/1)

  @doc "The highest floor round sector `index`, or its own."
  @spec highest_floor(World.t(), non_neg_integer()) :: float()
  def highest_floor(world, index), do: extreme(world, index, :floor, &Enum.max/1)

  @doc "The lowest floor of sector `index` and those round it."
  @spec lowest_floor(World.t(), non_neg_integer()) :: float()
  def lowest_floor(world, index) do
    floor = World.sector(world, index).floor
    world |> neighbours(index) |> Enum.map(& &1.floor) |> Enum.reduce(floor, &min/2)
  end

  @doc "The lowest floor round sector `index` above `height`, or `height` where there is none."
  @spec next_highest_floor(World.t(), non_neg_integer(), number()) :: number()
  def next_highest_floor(world, index, height) do
    world
    |> neighbours(index)
    |> Enum.map(& &1.floor)
    |> Enum.filter(&(&1 > height))
    |> Enum.min(fn -> height end)
  end

  @doc "The dimmest light of sector `index` and those round it."
  @spec min_light(World.t(), non_neg_integer()) :: integer()
  def min_light(world, index) do
    light = World.sector(world, index).light
    world |> neighbours(index) |> Enum.map(& &1.light) |> Enum.reduce(light, &min/2)
  end

  @doc "The brightest light round sector `index`, `0` where there is none."
  @spec max_light(World.t(), non_neg_integer()) :: integer()
  def max_light(world, index),
    do: world |> neighbours(index) |> Enum.map(& &1.light) |> Enum.max(fn -> 0 end)

  defp extreme(world, index, key, pick) do
    case neighbours(world, index) do
      [] -> Map.fetch!(World.sector(world, index), key)
      list -> list |> Enum.map(&Map.fetch!(&1, key)) |> pick.()
    end
  end

  @doc "The sectors tagged `tag`."
  @spec tagged(World.t(), integer()) :: [non_neg_integer()]
  def tagged(world, tag) do
    for index <- 0..(tuple_size(world.sectors) - 1)//1,
        World.sector(world, index).tag == tag,
        do: index
  end

  @doc "The bounding box `{top, bottom, left, right}` of sector `index`."
  @spec box(World.t(), non_neg_integer()) :: {float(), float(), float(), float()}
  def box(world, index) do
    key = {__MODULE__, :boxes, world.level}

    boxes =
      case :persistent_term.get(key, nil) do
        nil -> tap(boxes(world.map), &:persistent_term.put(key, &1))
        boxes -> boxes
      end

    elem(boxes, index)
  end

  defp boxes(map) do
    empty = {-1.0e9, 1.0e9, 1.0e9, -1.0e9}

    found =
      Enum.reduce(0..(tuple_size(map.lines) - 1)//1, %{}, fn index, acc ->
        ends = SectorMap.ends(map, index)

        [0, 1]
        |> Enum.map(&SectorMap.side_sector(map, index, &1))
        |> Enum.reject(&is_nil/1)
        |> Enum.reduce(acc, &Map.put(&2, &1, grow(Map.get(&2, &1, empty), ends)))
      end)

    List.to_tuple(
      for index <- 0..(tuple_size(map.sectors) - 1)//1, do: Map.get(found, index, empty)
    )
  end

  defp grow({top, bottom, left, right}, {{x1, y1}, {x2, y2}}),
    do:
      {Enum.max([top, y1, y2]), Enum.min([bottom, y1, y2]), Enum.min([left, x1, x2]),
       Enum.max([right, x1, x2])}

  @doc "Sound `name` heard from the middle of sector `index`; nothing for `nil`."
  @spec sound(World.t(), non_neg_integer(), String.t() | nil) :: World.t()
  def sound(world, _index, nil), do: world

  def sound(world, index, name) do
    {top, bottom, left, right} = box(world, index)
    World.sound(world, name, {(left + right) / 2, (top + bottom) / 2})
  end

  @doc "The height of the shortest lower texture on the sides round sector `index`."
  @spec shortest_lower(World.t(), non_neg_integer()) :: number()
  def shortest_lower(world, index) do
    pictures = Assets.get().graphics.pictures

    world.noise
    |> Map.get(index, [])
    |> Enum.flat_map(fn line_index ->
      line = elem(world.map.lines, line_index)
      [line.front, line.back]
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&elem(world.sides, &1).lower)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&elem(Pictures.size(pictures, &1), 1))
    |> Enum.min(fn -> 32_000 end)
  end
end
