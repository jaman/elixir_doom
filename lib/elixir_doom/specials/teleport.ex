defmodule ElixirDoom.Specials.Teleport do
  @moduledoc """
  Teleporters: a thing crossing a teleport line from its front arrives at the teleport
  destination in the tagged sector, facing its way, with fog and a sound at both ends.
  Missiles never teleport. A player arriving where something stands kills it; anything
  else finds the way blocked and stays.
  """

  alias Cauldron2D.Sectors.Map, as: SectorMap
  alias ElixirDoom.{Combat, Mobj, Player, World}

  @doc "Thing `mobj` crosses teleport `line` from `side` (`0`, the front, is the only way that works)."
  @spec cross(World.t(), map(), map(), 0 | 1) :: World.t()
  def cross(world, _mobj, _line, 1), do: world

  def cross(world, mobj, line, 0) do
    destination =
      world.mobjs
      |> Map.values()
      |> Enum.find(
        &(&1.type == :mt_teleportman and World.sector(world, &1.sector).tag == line.tag)
      )

    if destination == nil or Mobj.flag?(mobj, :missile),
      do: world,
      else: arrive(world, mobj, destination)
  end

  defp arrive(world, mobj, destination) do
    case stomp(world, mobj, destination) do
      {:blocked, world} -> world
      {:clear, world} -> move(world, mobj, destination)
    end
  end

  defp move(world, mobj, destination) do
    sector_index = SectorMap.sector_at(world.map, {destination.x, destination.y})
    sector = World.sector(world, sector_index)

    moved = %{
      mobj
      | x: destination.x,
        y: destination.y,
        z: sector.floor,
        floor: sector.floor,
        ceiling: sector.ceiling,
        sector: sector_index,
        momx: 0.0,
        momy: 0.0,
        momz: 0.0,
        angle: destination.angle,
        reaction: if(mobj.player != nil, do: 18, else: mobj.reaction)
    }

    ahead =
      {destination.x + 20 * :math.cos(destination.angle),
       destination.y + 20 * :math.sin(destination.angle), sector.floor}

    {world, _fog} = Mobj.spawn(world, :mt_tfog, {mobj.x, mobj.y, mobj.z})

    {world, _fog} =
      world
      |> World.sound("DSTELEPT", mobj)
      |> World.put_mobj(moved)
      |> Mobj.spawn(:mt_tfog, ahead)

    world = World.sound(world, "DSTELEPT", moved)

    if moved.player != nil,
      do: Player.update(world, moved.player, &%{&1 | view_z: moved.z + &1.view_height}),
      else: world
  end

  defp stomp(world, mobj, destination) do
    blockers =
      world.mobjs
      |> Map.values()
      |> Enum.filter(fn other ->
        other.id != mobj.id and Mobj.flag?(other, :shootable) and
          abs(other.x - destination.x) < other.radius + mobj.radius and
          abs(other.y - destination.y) < other.radius + mobj.radius
      end)

    cond do
      blockers == [] ->
        {:clear, world}

      mobj.player == nil ->
        {:blocked, world}

      true ->
        {:clear,
         Enum.reduce(blockers, world, &Combat.damage(&2, &1.id, mobj.id, mobj.id, 10_000))}
    end
  end
end
