defmodule ElixirDoom.Specials do
  @moduledoc """
  The level's machinery, as the rest of the game reaches it: lines that do something
  when used, walked over or shot; the sector specials a level starts with; floors that
  hurt; and running every machine once a tic.

  What each numbered line special does is a table here; the machines themselves are in
  `ElixirDoom.Specials.Doors`, `Floors`, `Plats`, `Ceilings`, `Lights`, `Switches` and
  `Teleport`, run by `ElixirDoom.Specials.Movers` and kept by
  `ElixirDoom.Specials.Machines`.
  """

  alias Cauldron2D.Sectors.Map, as: SectorMap
  alias Cauldron2D.Thinkers
  alias ElixirDoom.{Assets, Combat, Graphics, Mobj, World}

  alias ElixirDoom.Specials.{
    Ceilings,
    Doors,
    Floors,
    Lights,
    Movers,
    Plats,
    Switches,
    Teleport
  }

  @switch_actions %{
    7 => {{:stairs, :build8}, false},
    11 => {:exit, false},
    14 => {{:plat, :raise_and_change, 32}, false},
    15 => {{:plat, :raise_and_change, 24}, false},
    18 => {{:floor, :raise_to_nearest}, false},
    20 => {{:plat, :raise_to_nearest_and_change, 0}, false},
    21 => {{:plat, :down_wait_up_stay, 0}, false},
    23 => {{:floor, :lower_to_lowest}, false},
    29 => {{:door, :normal}, false},
    41 => {{:ceiling, :lower_to_floor}, false},
    49 => {{:ceiling, :crush_and_raise}, false},
    50 => {{:door, :close}, false},
    51 => {:secret_exit, false},
    55 => {{:floor, :raise_crush}, false},
    71 => {{:floor, :turbo_lower}, false},
    101 => {{:floor, :raise}, false},
    102 => {{:floor, :lower}, false},
    103 => {{:door, :open}, false},
    42 => {{:door, :close}, true},
    43 => {{:ceiling, :lower_to_floor}, true},
    45 => {{:floor, :lower}, true},
    60 => {{:floor, :lower_to_lowest}, true},
    61 => {{:door, :open}, true},
    62 => {{:plat, :down_wait_up_stay, 0}, true},
    63 => {{:door, :normal}, true},
    64 => {{:floor, :raise}, true},
    65 => {{:floor, :raise_crush}, true},
    66 => {{:plat, :raise_and_change, 24}, true},
    67 => {{:plat, :raise_and_change, 32}, true},
    68 => {{:plat, :raise_to_nearest_and_change, 0}, true},
    69 => {{:floor, :raise_to_nearest}, true},
    70 => {{:floor, :turbo_lower}, true}
  }

  @walk_actions %{
    2 => {{:door, :open}, true},
    3 => {{:door, :close}, true},
    4 => {{:door, :normal}, true},
    5 => {{:floor, :raise}, true},
    6 => {{:ceiling, :fast_crush_and_raise}, true},
    8 => {{:stairs, :build8}, true},
    10 => {{:plat, :down_wait_up_stay, 0}, true},
    12 => {{:lights, :max_neighbour}, true},
    13 => {{:lights, 255}, true},
    16 => {{:door, :close_30_then_open}, true},
    17 => {:strobe, true},
    19 => {{:floor, :lower}, true},
    22 => {{:plat, :raise_to_nearest_and_change, 0}, true},
    25 => {{:ceiling, :crush_and_raise}, true},
    30 => {{:floor, :raise_to_texture}, true},
    35 => {{:lights, 35}, true},
    36 => {{:floor, :turbo_lower}, true},
    37 => {{:floor, :lower_and_change}, true},
    38 => {{:floor, :lower_to_lowest}, true},
    39 => {:teleport, true},
    40 => {{:both, {:ceiling, :raise_to_highest}, {:floor, :lower_to_lowest}}, true},
    44 => {{:ceiling, :lower_and_crush}, true},
    52 => {:exit, false},
    53 => {{:plat, :perpetual_raise, 0}, true},
    54 => {:stop_plats, true},
    56 => {{:floor, :raise_crush}, true},
    57 => {:stop_ceilings, true},
    58 => {{:floor, :raise_24}, true},
    59 => {{:floor, :raise_24_change}, true},
    104 => {{:lights, :min_neighbour}, true},
    72 => {{:ceiling, :lower_and_crush}, false},
    73 => {{:ceiling, :crush_and_raise}, false},
    74 => {:stop_ceilings, false},
    75 => {{:door, :close}, false},
    76 => {{:door, :close_30_then_open}, false},
    77 => {{:ceiling, :fast_crush_and_raise}, false},
    79 => {{:lights, 35}, false},
    80 => {{:lights, :max_neighbour}, false},
    81 => {{:lights, 255}, false},
    82 => {{:floor, :lower_to_lowest}, false},
    83 => {{:floor, :lower}, false},
    84 => {{:floor, :lower_and_change}, false},
    86 => {{:door, :open}, false},
    87 => {{:plat, :perpetual_raise, 0}, false},
    88 => {{:plat, :down_wait_up_stay, 0}, false},
    89 => {:stop_plats, false},
    90 => {{:door, :normal}, false},
    91 => {{:floor, :raise}, false},
    92 => {{:floor, :raise_24}, false},
    93 => {{:floor, :raise_24_change}, false},
    94 => {{:floor, :raise_crush}, false},
    95 => {{:plat, :raise_to_nearest_and_change, 0}, false},
    96 => {{:floor, :raise_to_texture}, false},
    97 => {:teleport, false},
    98 => {{:floor, :turbo_lower}, false}
  }

  @shoot_actions %{
    24 => {{:floor, :raise}, false},
    46 => {{:door, :open}, true},
    47 => {{:plat, :raise_to_nearest_and_change, 0}, false}
  }

  @walking_monsters [39, 97, 125, 126, 4, 10, 88]
  @floor_damage %{5 => 10, 7 => 5, 4 => 20, 16 => 20}

  @doc "Start the machinery a level's sectors carry from the start: lights, timed doors, secrets."
  @spec spawn_sector_specials(World.t()) :: World.t()
  def spawn_sector_specials(world) do
    Enum.reduce(0..(tuple_size(world.sectors) - 1)//1, world, fn index, acc ->
      sector_special(acc, index, World.sector(acc, index).special)
    end)
  end

  defp sector_special(world, index, 1), do: Lights.flicker(world, index)

  defp sector_special(world, index, kind) when kind in [2, 3, 4, 12, 13] do
    dark = if kind in [2, 4, 13], do: 15, else: 35

    world
    |> Lights.strobe(index, dark, kind in [12, 13])
    |> World.update_sector(index, &%{&1 | special: if(kind == 4, do: 4, else: 0)})
  end

  defp sector_special(world, index, 8),
    do: world |> Lights.glow(index) |> World.update_sector(index, &%{&1 | special: 0})

  defp sector_special(world, _index, 9),
    do: %{world | totals: Map.update(world.totals, :secret_total, 1, &(&1 + 1))}

  defp sector_special(world, index, 10),
    do:
      world
      |> Doors.timed(index, :normal, 30 * 35)
      |> World.update_sector(index, &%{&1 | special: 0})

  defp sector_special(world, index, 14) do
    world
    |> Doors.timed(index, :raise_in_5_mins, 5 * 60 * 35)
    |> World.update_sector(index, &%{&1 | special: 0})
  end

  defp sector_special(world, _index, _special), do: world

  @doc "Run every machine once."
  @spec think(World.t()) :: World.t()
  def think(world) do
    {thinkers, world} = Thinkers.run(world.thinkers, %{world | thinkers: nil}, &think_one/3)
    scroll(%{world | thinkers: thinkers})
  end

  defp think_one(%{kind: kind} = light, id, world) when kind in [:flash, :strobe, :glow],
    do: Lights.step(light, id, world)

  defp think_one(%{kind: :button} = button, id, world), do: Switches.step(button, id, world)
  defp think_one(mover, id, world), do: Movers.step(mover, id, world)

  defp scroll(world) do
    sides =
      world.map.lines
      |> Tuple.to_list()
      |> Enum.filter(&(&1.special == 48))
      |> Enum.reduce(world.sides, fn line, acc ->
        put_elem(acc, line.front, Map.update!(elem(acc, line.front), :x_offset, &(&1 + 1)))
      end)

    %{world | sides: sides}
  end

  @doc "Thing `id` uses line `index` from `side`: `{:used, world}` or `{:unused, world}`."
  @spec use_line(World.t(), term(), non_neg_integer(), 0 | 1) :: {:used | :unused, World.t()}
  def use_line(world, id, index, side) do
    line = elem(world.map.lines, index)
    mobj = World.mobj(world, id)

    if usable?(world, mobj, index, line, side),
      do: {:used, use_special(world, id, index, line)},
      else: {:unused, world}
  end

  defp usable?(world, mobj, index, line, side) do
    line.special != 0 and not MapSet.member?(world.used, index) and
      (side == 0 or line.special == 124) and
      (mobj.player != nil or
         (not MapSet.member?(line.flags, :secret) and line.special in [1, 32, 33, 34]))
  end

  defp use_special(world, id, index, line) do
    if Doors.manual?(line.special),
      do: Doors.by_hand(world, id, index, line.special),
      else: switch(world, id, index, line, Map.get(@switch_actions, line.special))
  end

  defp switch(world, _id, _index, _line, nil), do: world

  defp switch(world, id, index, _line, {exit, _repeat?}) when exit in [:exit, :secret_exit] do
    world
    |> Switches.flip(index, false, true, id)
    |> Map.put(:exit, if(exit == :exit, do: :normal, else: :secret))
  end

  defp switch(world, id, index, line, {action, repeat?}) do
    mobj = World.mobj(world, id)

    case perform(world, action, line, {mobj, 0}) do
      {world, true} -> Switches.flip(world, index, repeat?, false, id)
      {world, false} -> world
    end
  end

  defp perform(world, {:door, type}, line, _actor), do: Doors.by_tag(world, line.tag, type)
  defp perform(world, {:floor, type}, line, _actor), do: Floors.by_tag(world, line, type)

  defp perform(world, {:plat, type, amount}, line, _actor),
    do: Plats.by_tag(world, line, type, amount)

  defp perform(world, {:ceiling, type}, line, _actor), do: Ceilings.by_tag(world, line.tag, type)
  defp perform(world, {:stairs, type}, line, _actor), do: Floors.stairs(world, line.tag, type)

  defp perform(world, {:lights, level}, line, _actor),
    do: {Lights.set_tagged(world, line.tag, level), true}

  defp perform(world, :strobe, line, _actor), do: {Lights.strobe_tagged(world, line.tag), true}
  defp perform(world, :stop_plats, line, _actor), do: {Plats.stop(world, line.tag), true}
  defp perform(world, :stop_ceilings, line, _actor), do: {Ceilings.stop(world, line.tag), true}
  defp perform(world, :exit, _line, _actor), do: {%{world | exit: :normal}, true}

  defp perform(world, :teleport, line, {mobj, side}),
    do: {Teleport.cross(world, mobj, line, side), true}

  defp perform(world, {:both, first, second}, line, actor) do
    {world, _started?} = perform(world, first, line, actor)
    perform(world, second, line, actor)
  end

  @doc "Thing `id` crossed `lines` this move: walk-over triggers."
  @spec cross_lines(World.t(), term(), [non_neg_integer()]) :: World.t()
  def cross_lines(world, _id, []), do: world

  def cross_lines(world, id, lines) do
    Enum.reduce(lines, world, fn index, acc ->
      line = elem(acc.map.lines, index)
      mobj = World.mobj(acc, id)

      if mobj != nil and walks?(acc, mobj, index, line),
        do: walk(acc, mobj, index, line),
        else: acc
    end)
  end

  defp walks?(world, mobj, index, line) do
    line.special != 0 and not MapSet.member?(world.used, index) and not Mobj.flag?(mobj, :missile) and
      (mobj.player != nil or line.special in @walking_monsters)
  end

  defp walk(world, mobj, index, line) do
    case Map.get(@walk_actions, line.special) do
      nil ->
        world

      {action, once?} ->
        {world, _started?} = perform(world, action, line, {mobj, crossed_from(world, mobj, line)})
        Switches.mark_used(world, index, once?)
    end
  end

  defp crossed_from(world, mobj, line) do
    {fx, fy} = SectorMap.vertex(world.map, line.from)
    {tx, ty} = SectorMap.vertex(world.map, line.to)
    1 - SectorMap.point_side({mobj.x, mobj.y}, {fx, fy, tx - fx, ty - fy})
  end

  @doc "A shot from thing `id` struck line `index`: gun-triggered lines."
  @spec shoot_line(World.t(), term(), non_neg_integer()) :: World.t()
  def shoot_line(world, id, index) do
    line = elem(world.map.lines, index)
    mobj = World.mobj(world, id)

    with false <- MapSet.member?(world.used, index),
         %{} <- mobj,
         true <- mobj.player != nil or line.special == 46,
         {action, repeat?} <- Map.get(@shoot_actions, line.special) do
      {world, _started?} = perform(world, action, line, {mobj, 0})
      Switches.flip(world, index, repeat?, false, id)
    else
      _nothing -> world
    end
  end

  @doc "Start door `type` in every sector tagged `tag`."
  @spec doors_by_tag(World.t(), integer(), atom()) :: World.t()
  def doors_by_tag(world, tag, type), do: world |> Doors.by_tag(tag, type) |> elem(0)

  @doc "Start floor movement `type` on every sector tagged `tag`."
  @spec floor_by_tag(World.t(), integer(), atom()) :: World.t()
  def floor_by_tag(world, tag, type), do: world |> Floors.by_tag(%{tag: tag}, type) |> elem(0)

  @doc "The floor under player `id` hurts, or holds a secret, or ends the level."
  @spec player_in_sector(World.t(), term()) :: World.t()
  def player_in_sector(world, id) do
    player = Map.fetch!(world.players, id)
    mobj = World.mobj(world, player.mobj)
    sector = World.sector(world, mobj.sector)

    if mobj.z != sector.floor,
      do: world,
      else: floor_special(world, player, mobj, sector.special)
  end

  defp floor_special(world, player, mobj, special) when is_map_key(@floor_damage, special) do
    suit? = Map.get(player.powers, :ironfeet, 0) > 0
    {roll, world} = World.random(world)
    shielded? = suit? and not (special in [4, 16] and roll < 5)

    if rem(world.tic, 32) == 0 and not shielded?,
      do: Combat.damage(world, mobj.id, nil, nil, Map.fetch!(@floor_damage, special)),
      else: world
  end

  defp floor_special(world, _player, mobj, 9),
    do: world |> World.count(:secrets) |> World.update_sector(mobj.sector, &%{&1 | special: 0})

  defp floor_special(world, _player, mobj, 11) do
    world =
      if rem(world.tic, 32) == 0, do: Combat.damage(world, mobj.id, nil, nil, 20), else: world

    case World.mobj(world, mobj.id) do
      %{health: health} when health <= 10 -> %{world | exit: :normal}
      _alive -> world
    end
  end

  defp floor_special(world, _player, _mobj, _special), do: world

  @doc "The sky flat's picture id."
  @spec sky_flat() :: non_neg_integer() | nil
  def sky_flat, do: Graphics.flat(Assets.get().graphics, "F_SKY1")
end
