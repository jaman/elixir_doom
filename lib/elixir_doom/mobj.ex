defmodule ElixirDoom.Mobj do
  @moduledoc """
  Things — players, monsters, missiles, pickups, decorations — and how each moves and
  changes state every tic.

      {world, id} = ElixirDoom.Mobj.spawn(world, :mt_troop, {x, y, :floor}, angle)
      world = ElixirDoom.Mobj.set_state(world, id, :s_troo_run1)
      world = ElixirDoom.Mobj.tick(world, id)

  A thing is a map with its type, position (`z` its feet), angle in radians, momentum,
  size, flags (a set of Doom's `MF_` names as atoms), health, state, and the bookkeeping
  monsters use to hunt. States come from `ElixirDoom.Info` and are run by
  `Cauldron2D.States`; their actions by `ElixirDoom.Actions`.
  """

  alias Cauldron2D.Sectors.Map, as: SectorMap
  alias Cauldron2D.Sectors.Move
  alias Cauldron2D.States
  alias ElixirDoom.{Actions, Combat, Info, Items, Specials, World}

  @stop_speed 1 / 16
  @float_speed 4.0
  @run_states [:s_play_run1, :s_play_run2, :s_play_run3, :s_play_run4]

  @doc "Spawn a thing of `type` at `{x, y, z}`, `z` a height or `:floor` or `:ceiling`."
  @spec spawn(World.t(), atom(), {number(), number(), number() | :floor | :ceiling}, number()) ::
          {World.t(), pos_integer()}
  def spawn(world, type, {x, y, z}, angle \\ 0.0) do
    info = Info.thing(type)
    sector_index = SectorMap.sector_at(world.map, {x, y})
    sector = World.sector(world, sector_index)
    spawn_state = info.spawn || :s_null
    state = Info.state(spawn_state)
    id = world.next_id

    z =
      case z do
        :floor -> sector.floor
        :ceiling -> sector.ceiling - info.height
        height -> height * 1.0
      end

    mobj = %{
      id: id,
      type: type,
      x: x * 1.0,
      y: y * 1.0,
      z: z,
      angle: angle * 1.0,
      momx: 0.0,
      momy: 0.0,
      momz: 0.0,
      radius: info.radius,
      height: info.height,
      flags: MapSet.new(info.flags),
      health: info.health,
      state: spawn_state,
      tics: state.tics,
      picture: state.picture,
      floor: sector.floor,
      ceiling: sector.ceiling,
      sector: sector_index,
      target: nil,
      tracer: nil,
      threshold: 0,
      reaction: if(world.skill == 5, do: 0, else: info.reaction),
      move_dir: nil,
      move_count: 0,
      player: nil,
      last_look: 0
    }

    {World.put_mobj(%{world | next_id: id + 1}, mobj), id}
  end

  @doc "Whether thing `mobj` has flag `flag`."
  @spec flag?(map(), atom()) :: boolean()
  def flag?(%{flags: flags}, flag), do: MapSet.member?(flags, flag)

  @doc "Thing `mobj` with `flag` set or cleared."
  @spec flag(map(), atom(), boolean()) :: map()
  def flag(mobj, flag, true), do: %{mobj | flags: MapSet.put(mobj.flags, flag)}
  def flag(mobj, flag, false), do: %{mobj | flags: MapSet.delete(mobj.flags, flag)}

  @doc "Thing type `mobj`'s definition."
  @spec info(map()) :: map()
  def info(%{type: type}), do: Info.thing(type)

  @doc "Put thing `id` into state `name`, running its actions; `nil` removes it."
  @spec set_state(World.t(), pos_integer(), atom() | nil) :: World.t()
  def set_state(world, id, name) do
    case World.mobj(world, id) do
      nil ->
        world

      mobj ->
        actor = %{state: mobj.state, tics: mobj.tics, picture: mobj.picture, world: world, id: id}
        actor |> States.enter(Info.states(), name, &act/2) |> settle()
    end
  end

  defp act(actor, action) do
    world = Actions.run(sync(actor), actor.id, action)

    case World.mobj(world, actor.id) do
      nil -> %{actor | world: world, state: nil, tics: -1}
      mobj -> %{actor | world: world, state: mobj.state, tics: mobj.tics, picture: mobj.picture}
    end
  end

  defp sync(actor) do
    World.update_mobj(
      actor.world,
      actor.id,
      &%{&1 | state: actor.state, tics: actor.tics, picture: actor.picture}
    )
  end

  defp settle(%{state: nil} = actor), do: World.remove_mobj(actor.world, actor.id)
  defp settle(actor), do: sync(actor)

  @doc "One tic of thing `id`: move it, let it fall, count its state down."
  @spec tick(World.t(), pos_integer()) :: World.t()
  def tick(world, id) do
    with %{} = mobj <- World.mobj(world, id),
         world <- if(moving?(mobj), do: xy_movement(world, id), else: world),
         %{} = mobj <- World.mobj(world, id),
         world <-
           if(mobj.z != mobj.floor or mobj.momz != 0, do: z_movement(world, id), else: world),
         %{} = mobj <- World.mobj(world, id) do
      count_down(world, mobj)
    else
      _gone -> world
    end
  end

  defp moving?(mobj), do: mobj.momx != 0 or mobj.momy != 0 or flag?(mobj, :skullfly)

  defp count_down(world, %{tics: -1}), do: world

  defp count_down(world, mobj) do
    if mobj.tics - 1 <= 0,
      do: set_state(world, mobj.id, Info.state(mobj.state).next),
      else: World.put_mobj(world, %{mobj | tics: mobj.tics - 1})
  end

  defp xy_movement(world, id) do
    mobj = World.mobj(world, id)

    if mobj.momx == 0 and mobj.momy == 0 do
      stop_skull(world, mobj)
    else
      max = World.tuning(world, :max_move)
      mobj = %{mobj | momx: clamp(mobj.momx, max), momy: clamp(mobj.momy, max)}
      world = World.put_mobj(world, mobj)

      world
      |> move_in_steps(id, {mobj.momx, mobj.momy}, max / 2)
      |> friction(id)
    end
  end

  defp stop_skull(world, mobj) do
    if flag?(mobj, :skullfly) do
      world
      |> World.put_mobj(%{flag(mobj, :skullfly, false) | momz: 0.0})
      |> set_state(mobj.id, info(mobj).spawn)
    else
      world
    end
  end

  defp clamp(value, max), do: value |> min(max) |> max(-max)

  defp move_in_steps(world, _id, {xmove, ymove}, _half) when xmove == 0 and ymove == 0, do: world

  defp move_in_steps(world, id, {xmove, ymove}, half) do
    case World.mobj(world, id) do
      nil ->
        world

      mobj ->
        {step, rest} =
          if abs(xmove) > half or abs(ymove) > half,
            do: {{xmove / 2, ymove / 2}, {xmove / 2, ymove / 2}},
            else: {{xmove, ymove}, {0, 0}}

        {sx, sy} = step

        case try_move(world, id, {mobj.x + sx, mobj.y + sy}) do
          {:ok, world} -> move_in_steps(world, id, rest, half)
          {:blocked, world, why} -> blocked_move(world, id, why)
        end
    end
  end

  defp blocked_move(world, id, why) do
    mobj = World.mobj(world, id)

    cond do
      mobj == nil ->
        world

      mobj.player != nil ->
        slide(world, mobj)

      flag?(mobj, :missile) ->
        if sky_hit?(world, why),
          do: World.remove_mobj(world, id),
          else: explode_missile(world, id)

      true ->
        World.put_mobj(world, %{mobj | momx: 0.0, momy: 0.0})
    end
  end

  defp sky_hit?(world, %{reason: reason, place: place}) when reason in [:ceiling, :tight] do
    sky = ElixirDoom.Graphics.flat(ElixirDoom.Assets.get().graphics, "F_SKY1")

    Enum.any?(place.lines, fn index ->
      Enum.any?(
        [0, 1],
        &(World.sector(world, SectorMap.side_sector(world.map, index, &1)).ceiling_picture == sky)
      )
    end)
  end

  defp sky_hit?(_world, _why), do: false

  defp slide(world, mobj) do
    {moved, {momx, momy}} =
      Move.slide(World.physics(world), body(mobj), {mobj.momx, mobj.momy}, move_opts(world, mobj))

    mobj = %{
      mobj
      | x: moved.x,
        y: moved.y,
        floor: moved.floor,
        ceiling: moved.ceiling,
        sector: moved.sector,
        momx: momx,
        momy: momy
    }

    world = World.put_mobj(world, mobj)
    Specials.cross_lines(world, mobj.id, moved.crossed)
  end

  defp friction(world, id) do
    case World.mobj(world, id) do
      nil ->
        world

      mobj ->
        cond do
          flag?(mobj, :missile) or flag?(mobj, :skullfly) -> world
          mobj.z > mobj.floor -> world
          corpse_sliding?(world, mobj) -> world
          stopping?(world, mobj) -> stop(world, mobj)
          true -> slow(world, mobj)
        end
    end
  end

  defp corpse_sliding?(world, mobj) do
    flag?(mobj, :corpse) and (abs(mobj.momx) > 0.25 or abs(mobj.momy) > 0.25) and
      mobj.floor != World.sector(world, mobj.sector).floor
  end

  defp stopping?(world, mobj) do
    abs(mobj.momx) < @stop_speed and abs(mobj.momy) < @stop_speed and
      (mobj.player == nil or not ElixirDoom.Player.pushing?(world, mobj.player))
  end

  defp stop(world, mobj) do
    world = World.put_mobj(world, %{mobj | momx: 0.0, momy: 0.0})

    if mobj.player != nil and mobj.state in @run_states,
      do: set_state(world, mobj.id, :s_play),
      else: world
  end

  defp slow(world, mobj) do
    friction = World.tuning(world, :friction)
    World.put_mobj(world, %{mobj | momx: mobj.momx * friction, momy: mobj.momy * friction})
  end

  defp z_movement(world, id) do
    mobj = World.mobj(world, id)
    gravity = World.tuning(world, :gravity)

    world =
      if mobj.player != nil and mobj.z < mobj.floor,
        do: ElixirDoom.Player.step_up(world, mobj.player, mobj.floor - mobj.z),
        else: world

    mobj = %{mobj | z: mobj.z + mobj.momz}
    mobj = float_toward_target(world, mobj)

    cond do
      mobj.z <= mobj.floor -> land(world, mobj, gravity)
      flag?(mobj, :nogravity) -> ceiling_check(world, mobj)
      mobj.momz == 0 -> ceiling_check(world, %{mobj | momz: -gravity * 2})
      true -> ceiling_check(world, %{mobj | momz: mobj.momz - gravity})
    end
  end

  defp float_toward_target(world, mobj) do
    with true <- flag?(mobj, :float) and mobj.target != nil,
         false <- flag?(mobj, :skullfly) or flag?(mobj, :infloat),
         %{} = target <- World.mobj(world, mobj.target) do
      distance = approx_distance(mobj, target)
      delta = target.z + mobj.height / 2 - mobj.z

      cond do
        delta < 0 and distance < -(delta * 3) -> %{mobj | z: mobj.z - @float_speed}
        delta > 0 and distance < delta * 3 -> %{mobj | z: mobj.z + @float_speed}
        true -> mobj
      end
    else
      _not_floating -> mobj
    end
  end

  defp land(world, mobj, gravity) do
    mobj = if flag?(mobj, :skullfly), do: %{mobj | momz: -mobj.momz}, else: mobj

    world =
      if mobj.momz < 0 and mobj.player != nil and mobj.momz < -gravity * 8 do
        world
        |> ElixirDoom.Player.squat(mobj.player, mobj.momz / 8)
        |> World.sound("DSOOF", mobj)
      else
        world
      end

    mobj = %{mobj | z: mobj.floor, momz: if(mobj.momz < 0, do: 0.0, else: mobj.momz)}
    world = World.put_mobj(world, mobj)

    if flag?(mobj, :missile) and not flag?(mobj, :noclip),
      do: explode_missile(world, mobj.id),
      else: world
  end

  defp ceiling_check(world, mobj) do
    if mobj.z + mobj.height > mobj.ceiling do
      momz = if flag?(mobj, :skullfly), do: -mobj.momz, else: min(mobj.momz, 0.0)
      mobj = %{mobj | z: mobj.ceiling - mobj.height, momz: momz}
      world = World.put_mobj(world, mobj)

      if flag?(mobj, :missile) and not flag?(mobj, :noclip),
        do: explode_missile(world, mobj.id),
        else: world
    else
      World.put_mobj(world, mobj)
    end
  end

  @doc "The body `Cauldron2D.Sectors.Move` moves for thing `mobj`."
  @spec body(map()) :: Move.body()
  def body(mobj), do: %{x: mobj.x, y: mobj.y, z: mobj.z, radius: mobj.radius, height: mobj.height}

  @doc "The movement options for thing `mobj`."
  @spec move_opts(World.t(), map()) :: keyword()
  def move_opts(world, mobj) do
    lines = world.map.lines

    line_blocks? =
      cond do
        flag?(mobj, :missile) -> fn _index -> false end
        mobj.player != nil -> fn index -> MapSet.member?(elem(lines, index).flags, :blocks) end
        true -> fn index -> blocks_walker?(elem(lines, index).flags) end
      end

    [
      step: World.tuning(world, :step),
      dropoff: mobj.player != nil or flag?(mobj, :dropoff) or flag?(mobj, :float),
      line_blocks?: line_blocks?,
      body_blocks?: fn {other_id, _point, _radius} -> blocks_thing?(world, mobj, other_id) end,
      except: mobj.id
    ]
  end

  defp blocks_walker?(flags),
    do: MapSet.member?(flags, :blocks) or MapSet.member?(flags, :blocks_walkers)

  defp blocks_thing?(world, mobj, other_id) do
    other = World.mobj(world, other_id)
    other != nil and touchable?(other) and blocks_as?(mobj, other)
  end

  defp touchable?(other),
    do: flag?(other, :solid) or flag?(other, :special) or flag?(other, :shootable)

  defp blocks_as?(mobj, other) do
    cond do
      flag?(mobj, :missile) -> missile_hits?(mobj, other)
      flag?(mobj, :skullfly) -> flag?(other, :solid) or flag?(other, :shootable)
      true -> flag?(other, :solid)
    end
  end

  defp missile_hits?(missile, other) do
    cond do
      missile.z > other.z + other.height -> false
      missile.z + missile.height < other.z -> false
      other.id == missile.target -> false
      true -> flag?(other, :shootable) or flag?(other, :solid)
    end
  end

  @doc """
  Move thing `id` to `point` if it fits, picking up what it touches and triggering the
  lines it crosses: `{:ok, world}` or `{:blocked, world, why}`, `why` as
  `Cauldron2D.Sectors.Move.try/4` reports it, with `floats?: true` where only its height
  was wrong.
  """
  @spec try_move(World.t(), pos_integer(), {number(), number()}) ::
          {:ok, World.t()} | {:blocked, World.t(), map()}
  def try_move(world, id, point) do
    mobj = World.mobj(world, id)

    case Move.try(World.physics(world), body(mobj), point, move_opts(world, mobj)) do
      {:ok, moved} ->
        mobj = %{
          mobj
          | x: moved.x,
            y: moved.y,
            floor: moved.floor,
            ceiling: moved.ceiling,
            sector: moved.sector
        }

        world = World.put_mobj(world, mobj)
        world = touch(world, mobj, moved.bodies)
        {:ok, Specials.cross_lines(world, id, moved.crossed)}

      {:blocked, why} ->
        {:blocked, struck(world, mobj, why),
         Map.put(why, :floats?, why.reason in [:ceiling, :step])}
    end
  end

  defp touch(world, mobj, bodies) do
    if flag?(mobj, :pickup) and mobj.player != nil,
      do:
        Enum.reduce(bodies, world, fn {other_id, _point, _radius}, acc ->
          pick_up(acc, other_id, mobj.id)
        end),
      else: world
  end

  defp pick_up(world, item_id, toucher_id) do
    case World.mobj(world, item_id) do
      %{} = item ->
        if flag?(item, :special), do: Items.touch(world, item_id, toucher_id), else: world

      nil ->
        world
    end
  end

  defp struck(world, mobj, %{place: %{blocked: {:body, other_id}}}) do
    cond do
      flag?(mobj, :missile) -> impact(world, mobj, other_id, mobj.target)
      flag?(mobj, :skullfly) -> world |> impact(mobj, other_id, mobj.id) |> land_skull(mobj.id)
      true -> world
    end
  end

  defp struck(world, _mobj, _why), do: world

  defp impact(world, mobj, other_id, source) do
    {roll, world} = World.random(world)
    Combat.damage(world, other_id, mobj.id, source, (rem(roll, 8) + 1) * info(mobj).damage)
  end

  defp land_skull(world, id) do
    case World.mobj(world, id) do
      nil ->
        world

      skull ->
        world
        |> World.put_mobj(%{flag(skull, :skullfly, false) | momx: 0.0, momy: 0.0, momz: 0.0})
        |> set_state(id, info(skull).spawn)
    end
  end

  @doc "Thing `id`, a missile, bursts where it is."
  @spec explode_missile(World.t(), pos_integer()) :: World.t()
  def explode_missile(world, id) do
    case World.mobj(world, id) do
      nil ->
        world

      mobj ->
        info = info(mobj)

        world =
          World.put_mobj(world, flag(%{mobj | momx: 0.0, momy: 0.0, momz: 0.0}, :missile, false))

        world = set_state(world, id, info.death)
        {roll, world} = World.random(world)

        world =
          World.update_mobj(world, id, fn m ->
            %{m | tics: max(1, m.tics - Bitwise.band(roll, 3))}
          end)

        World.sound(world, info.death_sound, mobj)
    end
  end

  @doc "Doom's quick distance: the longer side plus half the shorter."
  @spec approx_distance(map(), map()) :: float()
  def approx_distance(a, b) do
    dx = abs(a.x - b.x)
    dy = abs(a.y - b.y)
    dx + dy - min(dx, dy) / 2
  end

  @doc "The angle from thing `a` to `b`, in radians."
  @spec angle_to(map(), map()) :: float()
  def angle_to(a, b), do: :math.atan2(b.y - a.y, b.x - a.x)
end
