defmodule ElixirDoom.Specials.Movers do
  @moduledoc """
  Doors, lifts, floors and ceilings moving a tic at a time, and what moving a plane does
  to the things in its sector: lifting them, stopping against them, crushing them.

  `step/3` is a `Cauldron2D.Thinkers` step for a mover of kind `:door`, `:plat`, `:floor`
  or `:ceiling`, answering `{:keep, mover, world}` or `{:done, world}`.
  """

  alias Cauldron2D.Sectors.Move
  alias ElixirDoom.{Combat, Mobj, World}
  alias ElixirDoom.Specials.{Machines, Sectors}

  @plat_ends [:down_wait_up_stay, :blaze_dwus, :raise_and_change, :raise_to_nearest_and_change]

  @doc "One tic of `mover`."
  @spec step(map(), pos_integer(), World.t()) :: {:keep, map(), World.t()} | {:done, World.t()}
  def step(%{kind: :door} = door, _id, world), do: door(door, world)
  def step(%{kind: :plat} = plat, _id, world), do: plat(plat, world)
  def step(%{kind: :floor} = floor, _id, world), do: floor(floor, world)
  def step(%{kind: :ceiling} = ceiling, _id, world), do: ceiling(ceiling, world)

  defp door(%{direction: direction, countdown: countdown} = door, world)
       when direction in [0, 2] and countdown > 1,
       do: {:keep, %{door | countdown: countdown - 1}, world}

  defp door(%{direction: 0, type: type} = door, world) when type in [:normal, :blaze_raise] do
    sound = if type == :blaze_raise, do: "DSBDCLS", else: "DSDORCLS"
    {:keep, %{door | direction: -1}, Sectors.sound(world, door.sector, sound)}
  end

  defp door(%{direction: 0, type: :close_30_then_open} = door, world),
    do: {:keep, %{door | direction: 1}, Sectors.sound(world, door.sector, "DSDOROPN")}

  defp door(%{direction: 0} = door, world), do: {:keep, door, world}

  defp door(%{direction: 2} = door, world),
    do:
      {:keep, %{door | direction: 1, type: :normal},
       Sectors.sound(world, door.sector, "DSDOROPN")}

  defp door(%{direction: -1} = door, world) do
    floor = World.sector(world, door.sector).floor
    {result, world} = move_plane(world, door.sector, {door.speed, floor, false}, {:ceiling, -1})
    door_down(result, door, world)
  end

  defp door(%{direction: 1} = door, world) do
    {result, world} = move_plane(world, door.sector, {door.speed, door.top, false}, {:ceiling, 1})

    cond do
      result != :pastdest ->
        {:keep, door, world}

      door.type in [:normal, :blaze_raise] ->
        {:keep, %{door | direction: 0, countdown: door.wait}, world}

      true ->
        {:done, Machines.release(world, door.sector)}
    end
  end

  defp door_down(:pastdest, %{type: type} = door, world)
       when type in [:normal, :close, :blaze_raise, :blaze_close] do
    sound = if type in [:blaze_raise, :blaze_close], do: "DSBDCLS"
    {:done, world |> Machines.release(door.sector) |> Sectors.sound(door.sector, sound)}
  end

  defp door_down(:pastdest, %{type: :close_30_then_open} = door, world),
    do: {:keep, %{door | direction: 0, countdown: 35 * 30}, world}

  defp door_down(:crushed, %{type: type} = door, world) when type not in [:close, :blaze_close],
    do: {:keep, %{door | direction: 1}, Sectors.sound(world, door.sector, "DSDOROPN")}

  defp door_down(_result, door, world), do: {:keep, door, world}

  defp plat(%{status: :up} = plat, world) do
    {result, world} =
      move_plane(world, plat.sector, {plat.speed, plat.high, plat.crush}, {:floor, 1})

    world = grind(world, plat)

    cond do
      result == :crushed and not plat.crush ->
        {:keep, %{plat | count: plat.wait, status: :down},
         Sectors.sound(world, plat.sector, "DSPSTART")}

      result == :pastdest ->
        plat_arrived(plat, Sectors.sound(world, plat.sector, "DSPSTOP"))

      true ->
        {:keep, plat, world}
    end
  end

  defp plat(%{status: :down} = plat, world) do
    {result, world} = move_plane(world, plat.sector, {plat.speed, plat.low, false}, {:floor, -1})

    if result == :pastdest,
      do:
        {:keep, %{plat | count: plat.wait, status: :waiting},
         Sectors.sound(world, plat.sector, "DSPSTOP")},
      else: {:keep, plat, world}
  end

  defp plat(%{status: :waiting, count: count} = plat, world) when count > 1,
    do: {:keep, %{plat | count: count - 1}, world}

  defp plat(%{status: :waiting} = plat, world) do
    status = if World.sector(world, plat.sector).floor == plat.low, do: :up, else: :down
    {:keep, %{plat | status: status}, Sectors.sound(world, plat.sector, "DSPSTART")}
  end

  defp plat(plat, world), do: {:keep, plat, world}

  defp plat_arrived(%{type: type} = plat, world) when type in @plat_ends,
    do: {:done, Machines.release(world, plat.sector)}

  defp plat_arrived(plat, world), do: {:keep, %{plat | count: plat.wait, status: :waiting}, world}

  defp grind(world, %{type: type} = plat)
       when type in [:raise_and_change, :raise_to_nearest_and_change],
       do:
         if(rem(world.tic, 8) == 0,
           do: Sectors.sound(world, plat.sector, "DSSTNMOV"),
           else: world
         )

  defp grind(world, _plat), do: world

  defp floor(floor, world) do
    plan = {floor.speed, floor.destination, floor.crush}
    {result, world} = move_plane(world, floor.sector, plan, {:floor, floor.direction})

    world =
      if rem(world.tic, 8) == 0, do: Sectors.sound(world, floor.sector, "DSSTNMOV"), else: world

    if result == :pastdest,
      do:
        {:done,
         world
         |> change(floor)
         |> Machines.release(floor.sector)
         |> Sectors.sound(floor.sector, "DSPSTOP")},
      else: {:keep, floor, world}
  end

  defp change(world, %{change: nil}), do: world

  defp change(world, %{change: change, sector: sector}),
    do: World.update_sector(world, sector, &Map.merge(&1, change))

  defp ceiling(%{status: :stasis} = ceiling, world), do: {:keep, ceiling, world}

  defp ceiling(%{direction: 1} = ceiling, world) do
    {result, world} =
      move_plane(world, ceiling.sector, {ceiling.speed, ceiling.top, false}, {:ceiling, 1})

    world = grind_ceiling(world, ceiling)

    cond do
      result != :pastdest -> {:keep, ceiling, world}
      ceiling.type == :raise_to_highest -> {:done, Machines.release(world, ceiling.sector)}
      true -> {:keep, %{ceiling | direction: -1}, world}
    end
  end

  defp ceiling(%{direction: -1} = ceiling, world) do
    plan = {ceiling.speed, ceiling.bottom, ceiling.crush}
    {result, world} = move_plane(world, ceiling.sector, plan, {:ceiling, -1})
    ceiling_down(result, ceiling, grind_ceiling(world, ceiling))
  end

  defp ceiling_down(:pastdest, %{type: type} = ceiling, world)
       when type in [:crush_and_raise, :silent_crush_and_raise],
       do: {:keep, %{ceiling | direction: 1, speed: 1.0}, world}

  defp ceiling_down(:pastdest, %{type: :fast_crush_and_raise} = ceiling, world),
    do: {:keep, %{ceiling | direction: 1}, world}

  defp ceiling_down(:pastdest, ceiling, world),
    do: {:done, Machines.release(world, ceiling.sector)}

  defp ceiling_down(:crushed, %{type: type} = ceiling, world)
       when type in [:crush_and_raise, :silent_crush_and_raise, :lower_and_crush],
       do: {:keep, %{ceiling | speed: 1 / 8}, world}

  defp ceiling_down(_result, ceiling, world), do: {:keep, ceiling, world}

  defp grind_ceiling(world, %{type: :silent_crush_and_raise}), do: world

  defp grind_ceiling(world, ceiling),
    do:
      if(rem(world.tic, 8) == 0,
        do: Sectors.sound(world, ceiling.sector, "DSSTNMOV"),
        else: world
      )

  defp move_plane(world, sector, {speed, destination, crush}, {plane, direction}) do
    last = Map.fetch!(World.sector(world, sector), plane)
    wanted = last + speed * direction
    past? = if direction == 1, do: wanted > destination, else: wanted < destination

    {world, blocked?} =
      place_plane(world, sector, plane, if(past?, do: destination, else: wanted), crush)

    case outcome(past?, blocked?, crush, {plane, direction}) do
      {result, :revert} -> {result, revert(world, sector, plane, last, crush)}
      {result, :stay} -> {result, world}
    end
  end

  defp outcome(true, true, _crush, _motion), do: {:pastdest, :revert}
  defp outcome(true, false, _crush, _motion), do: {:pastdest, :stay}
  defp outcome(false, false, _crush, _motion), do: {:ok, :stay}
  defp outcome(false, true, _crush, {:ceiling, 1}), do: {:ok, :stay}
  defp outcome(false, true, _crush, {:floor, -1}), do: {:crushed, :revert}
  defp outcome(false, true, true, _motion), do: {:crushed, :stay}
  defp outcome(false, true, false, _motion), do: {:crushed, :revert}

  defp place_plane(world, sector, plane, height, crush) do
    world
    |> World.update_sector(sector, &Map.put(&1, plane, height))
    |> things_in(sector, crush)
  end

  defp revert(world, sector, plane, height, crush),
    do: world |> place_plane(sector, plane, height, crush) |> elem(0)

  defp things_in(world, sector, crush) do
    {top, bottom, left, right} = Sectors.box(world, sector)

    world.mobjs
    |> Map.values()
    |> Enum.filter(fn mobj ->
      mobj.x + mobj.radius > left and mobj.x - mobj.radius < right and
        mobj.y + mobj.radius > bottom and mobj.y - mobj.radius < top
    end)
    |> Enum.reduce({world, false}, fn mobj, {acc, blocked?} ->
      {acc, fits?} = height_clip(acc, mobj, crush)
      {acc, blocked? or not fits?}
    end)
  end

  defp height_clip(world, mobj, crush) do
    if Mobj.flag?(mobj, :noblockmap) and not Mobj.flag?(mobj, :missile) do
      {world, true}
    else
      place =
        Move.check(World.physics(world), Mobj.body(mobj), {mobj.x, mobj.y},
          except: mobj.id,
          body_blocks?: fn _ -> false end
        )

      mobj = %{mobj | floor: place.floor, ceiling: place.ceiling, z: settled_z(mobj, place)}
      world = World.put_mobj(world, mobj)

      if place.ceiling - place.floor >= mobj.height,
        do: {world, true},
        else: squash(world, mobj, crush)
    end
  end

  defp settled_z(mobj, place) do
    cond do
      mobj.z == mobj.floor -> place.floor
      mobj.z + mobj.height > place.ceiling -> place.ceiling - mobj.height
      true -> mobj.z
    end
  end

  defp squash(world, mobj, crush) do
    cond do
      mobj.health <= 0 ->
        world =
          World.put_mobj(world, %{Mobj.flag(mobj, :solid, false) | height: 0.0, radius: 0.0})

        {Mobj.set_state(world, mobj.id, :s_gibs), true}

      Mobj.flag?(mobj, :dropped) ->
        {World.remove_mobj(world, mobj.id), true}

      not Mobj.flag?(mobj, :shootable) ->
        {world, true}

      crush and rem(world.tic, 4) == 0 ->
        {Combat.damage(world, mobj.id, nil, nil, 10), false}

      true ->
        {world, false}
    end
  end
end
