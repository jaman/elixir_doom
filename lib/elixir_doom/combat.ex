defmodule ElixirDoom.Combat do
  @moduledoc """
  Hurting and killing: damage with its knockback, armour and pain; death and what a
  monster drops; instant-hit shots and the aim that picks their target; missiles; and
  blasts that hurt everything in sight of them.
  """

  alias Cauldron2D.Sectors.Map, as: SectorMap
  alias Cauldron2D.Sectors.{Move, Sight, Trace}
  alias ElixirDoom.{Mobj, Player, Specials, World}

  @aim_slope 100 / 160
  @base_threshold 100
  @drops %{
    mt_possessed: :mt_clip,
    mt_shotguy: :mt_shotgun,
    mt_chainguy: :mt_chaingun,
    mt_wolfss: :mt_clip
  }

  @doc "Thing `target_id` takes `damage` from `inflictor_id`, caused by `source_id`."
  @spec damage(World.t(), term(), term() | nil, term() | nil, number()) :: World.t()
  def damage(world, target_id, inflictor_id, source_id, damage) do
    case World.mobj(world, target_id) do
      %{} = target ->
        if Mobj.flag?(target, :shootable) and target.health > 0,
          do:
            hurt(
              world,
              target,
              World.mobj(world, inflictor_id),
              source_id && World.mobj(world, source_id),
              damage
            ),
          else: world

      nil ->
        world
    end
  end

  defp hurt(world, target, inflictor, source, damage) do
    target =
      if Mobj.flag?(target, :skullfly),
        do: %{Mobj.flag(target, :skullfly, false) | momx: 0.0, momy: 0.0, momz: 0.0},
        else: target

    damage = if target.player != nil and world.skill == 1, do: damage / 2, else: damage
    {target, world} = knockback(world, target, inflictor, source, damage)
    world = World.put_mobj(world, target)

    {world, damage} =
      if target.player != nil,
        do: Player.absorb(world, target.player, damage, source),
        else: {world, damage}

    case World.mobj(world, target.id) do
      nil ->
        world

      target ->
        target = %{target | health: target.health - trunc(damage)}
        world = World.put_mobj(world, target)

        world =
          if target.player != nil,
            do: Player.hurt(world, target.player, target.health, damage, source),
            else: world

        if target.health <= 0,
          do: kill(world, target.id, source),
          else: pain(world, target.id, source)
    end
  end

  defp knockback(world, target, nil, _source, _damage), do: {target, world}

  defp knockback(world, target, inflictor, source, damage) do
    if Mobj.flag?(target, :noclip) or Player.sawing?(world, source) do
      {target, world}
    else
      angle = Mobj.angle_to(inflictor, target)
      thrust = damage * 12.5 / Mobj.info(target).mass
      {roll, world} = World.random(world)

      {angle, thrust} =
        if damage < 40 and damage > target.health and target.z - inflictor.z > 64 and
             Bitwise.band(roll, 1) == 1,
           do: {angle + :math.pi(), thrust * 4},
           else: {angle, thrust}

      {%{
         target
         | momx: target.momx + thrust * :math.cos(angle),
           momy: target.momy + thrust * :math.sin(angle)
       }, world}
    end
  end

  defp pain(world, id, source) do
    target = World.mobj(world, id)
    info = Mobj.info(target)
    {roll, world} = World.random(world)

    world =
      if roll < info.pain_chance and not Mobj.flag?(target, :skullfly) and info.pain != nil do
        world
        |> World.put_mobj(Mobj.flag(target, :justhit, true))
        |> Mobj.set_state(id, info.pain)
      else
        world
      end

    case World.mobj(world, id) do
      nil -> world
      target -> World.put_mobj(world, provoke(target, source))
    end
    |> wake(id, source)
  end

  defp provoke(target, source) do
    target = %{target | reaction: 0}

    if (target.threshold == 0 or target.type == :mt_vile) and source != nil and
         source.id != target.id and
         target.player == nil,
       do: %{target | target: source.id, threshold: @base_threshold},
       else: target
  end

  defp wake(world, id, source) do
    case World.mobj(world, id) do
      %{} = target when source != nil ->
        info = Mobj.info(target)

        if target.state == info.spawn and info.see != nil and target.player == nil,
          do: Mobj.set_state(world, id, info.see),
          else: world

      _other ->
        world
    end
  end

  @doc "Thing `id` dies, killed by `source`."
  @spec kill(World.t(), term(), map() | nil) :: World.t()
  def kill(world, id, source) do
    target = World.mobj(world, id)
    info = Mobj.info(target)

    target =
      target
      |> Mobj.flag(:shootable, false)
      |> Mobj.flag(:float, false)
      |> Mobj.flag(:skullfly, false)
      |> Mobj.flag(:corpse, true)
      |> Mobj.flag(:dropoff, true)

    target = if target.type != :mt_skull, do: Mobj.flag(target, :nogravity, false), else: target
    target = %{target | height: target.height / 4}
    world = World.put_mobj(world, target)
    world = if Mobj.flag?(target, :countkill), do: World.count(world, :kills), else: world
    world = if target.player != nil, do: Player.die(world, target.player, source), else: world
    gibbed? = target.health < -info.health and info.xdeath != nil
    world = Mobj.set_state(world, id, if(gibbed?, do: info.xdeath, else: info.death))
    {roll, world} = World.random(world)

    world =
      World.update_mobj(world, id, fn m -> %{m | tics: max(1, m.tics - Bitwise.band(roll, 3))} end)

    drop(world, target)
  end

  defp drop(world, target) do
    case Map.get(@drops, target.type) do
      nil ->
        world

      item ->
        {world, drop_id} = Mobj.spawn(world, item, {target.x, target.y, :floor})
        World.update_mobj(world, drop_id, &Mobj.flag(&1, :dropped, true))
    end
  end

  @doc """
  Aim from thing `shooter_id` along `angle` up to `range`: `{slope, target_id}` toward the
  first shootable thing whose middle the line can reach, or `{0.0, nil}`.
  """
  @spec aim(World.t(), term(), number(), number()) :: {float(), term() | nil}
  def aim(world, shooter_id, angle, range) do
    shooter = World.mobj(world, shooter_id)
    z = shooter.z + shooter.height / 2 + 8
    to = {shooter.x + range * :math.cos(angle), shooter.y + range * :math.sin(angle)}

    world.map
    |> Trace.run(world.blockmap, {shooter.x, shooter.y}, to, except: shooter_id)
    |> Enum.reduce_while({@aim_slope, -@aim_slope}, fn intercept, {top, bottom} ->
      aim_step(world, intercept, {top, bottom}, z, range, shooter_id)
    end)
    |> case do
      {:target, slope, id} -> {slope, id}
      _missed -> {0.0, nil}
    end
  end

  defp aim_step(world, %{line: index, fraction: fraction}, {top, bottom}, z, range, _shooter) do
    case Move.opening(World.physics(world), index) do
      nil ->
        {:halt, :missed}

      %{range: open} when open <= 0 ->
        {:halt, :missed}

      opening ->
        distance = max(range * fraction, 1.0)
        {front, back} = line_sectors(world, index)

        bottom =
          if front.floor != back.floor,
            do: max(bottom, (opening.bottom - z) / distance),
            else: bottom

        top =
          if front.ceiling != back.ceiling, do: min(top, (opening.top - z) / distance), else: top

        if top <= bottom, do: {:halt, :missed}, else: {:cont, {top, bottom}}
    end
  end

  defp aim_step(world, %{body: id, fraction: fraction}, slopes, z, range, _shooter) do
    case World.mobj(world, id) do
      %{} = thing -> aim_at(thing, slopes, z, max(range * fraction, 1.0))
      nil -> {:cont, slopes}
    end
  end

  defp aim_at(thing, {top, bottom} = slopes, z, distance) do
    thing_top = min((thing.z + thing.height - z) / distance, top)
    thing_bottom = max((thing.z - z) / distance, bottom)

    cond do
      not Mobj.flag?(thing, :shootable) -> {:cont, slopes}
      thing_top < bottom or thing_bottom > top -> {:cont, slopes}
      true -> {:halt, {:target, (thing_top + thing_bottom) / 2, thing.id}}
    end
  end

  defp line_sectors(world, index) do
    {World.sector(world, SectorMap.side_sector(world.map, index, 0)),
     World.sector(world, SectorMap.side_sector(world.map, index, 1))}
  end

  @doc """
  An instant-hit shot from `shooter_id` along `angle` at `slope`, `range` long: the first
  wall it meets gets a puff, the first thing in its path `damage` and blood.
  """
  @spec line_attack(World.t(), term(), number(), number(), number(), number()) :: World.t()
  def line_attack(world, shooter_id, angle, range, slope, damage) do
    shooter = World.mobj(world, shooter_id)
    z = shooter.z + shooter.height / 2 + 8
    to = {shooter.x + range * :math.cos(angle), shooter.y + range * :math.sin(angle)}

    shot = %{
      from: {shooter.x, shooter.y},
      to: to,
      z: z,
      slope: slope,
      range: range,
      damage: damage,
      shooter: shooter_id
    }

    world.map
    |> Trace.run(world.blockmap, shot.from, to, except: shooter_id)
    |> Enum.reduce_while(world, &shot_step(&2, &1, shot))
  end

  defp shot_step(world, %{line: index, fraction: fraction}, shot) do
    line = elem(world.map.lines, index)
    world = if line.special != 0, do: Specials.shoot_line(world, shot.shooter, index), else: world

    case Move.opening(World.physics(world), index) do
      nil ->
        {:halt, puff_at(world, shot, fraction, index)}

      opening ->
        distance = max(shot.range * fraction, 1.0)
        {front, back} = line_sectors(world, index)

        through? =
          (front.floor == back.floor or (opening.bottom - shot.z) / distance <= shot.slope) and
            (front.ceiling == back.ceiling or (opening.top - shot.z) / distance >= shot.slope)

        if through?, do: {:cont, world}, else: {:halt, puff_at(world, shot, fraction, index)}
    end
  end

  defp shot_step(world, %{body: id, fraction: fraction}, shot) do
    thing = World.mobj(world, id)

    if thing != nil and in_line?(thing, shot, max(shot.range * fraction, 1.0)),
      do: {:halt, hit(world, thing, shot, fraction)},
      else: {:cont, world}
  end

  defp in_line?(thing, shot, distance) do
    Mobj.flag?(thing, :shootable) and (thing.z + thing.height - shot.z) / distance >= shot.slope and
      (thing.z - shot.z) / distance <= shot.slope
  end

  defp hit(world, thing, shot, fraction) do
    at = point(shot, fraction - 10 / shot.range)

    world =
      if Mobj.flag?(thing, :noblood), do: puff(world, at), else: blood(world, at, shot.damage)

    damage(world, thing.id, shot.shooter, shot.shooter, shot.damage)
  end

  defp puff_at(world, shot, fraction, index) do
    {x, y, z} = point(shot, fraction - 4 / shot.range)
    sky = ElixirDoom.Graphics.flat(ElixirDoom.Assets.get().graphics, "F_SKY1")
    sector = World.sector(world, SectorMap.side_sector(world.map, index, 0))

    if sector.ceiling_picture == sky and z > sector.ceiling,
      do: world,
      else: puff(world, {x, y, z})
  end

  defp point(shot, fraction) do
    {fx, fy} = shot.from
    {tx, ty} = shot.to

    {fx + (tx - fx) * fraction, fy + (ty - fy) * fraction,
     shot.z + shot.slope * shot.range * fraction}
  end

  @doc "A puff of smoke where a shot struck."
  @spec puff(World.t(), {number(), number(), number()}) :: World.t()
  def puff(world, {x, y, z}) do
    {spread, world} = World.random_spread(world)
    {world, id} = Mobj.spawn(world, :mt_puff, {x, y, z + spread / 64})
    {roll, world} = World.random(world)

    World.update_mobj(world, id, fn m ->
      %{m | momz: 1.0, tics: max(1, m.tics - Bitwise.band(roll, 3))}
    end)
  end

  defp blood(world, {x, y, z}, damage) do
    {spread, world} = World.random_spread(world)
    {world, id} = Mobj.spawn(world, :mt_blood, {x, y, z + spread / 64})
    {roll, world} = World.random(world)

    world =
      World.update_mobj(world, id, fn m ->
        %{m | momz: 2.0, tics: max(1, m.tics - Bitwise.band(roll, 3))}
      end)

    cond do
      damage <= 12 and damage >= 9 -> Mobj.set_state(world, id, :s_blood2)
      damage < 9 -> Mobj.set_state(world, id, :s_blood3)
      true -> world
    end
  end

  @doc "A missile of `type` from `source_id` at `dest_id`."
  @spec missile(World.t(), term(), term(), atom()) :: World.t()
  def missile(world, source_id, dest_id, type) do
    with %{} = source <- World.mobj(world, source_id),
         %{} = dest <- World.mobj(world, dest_id) do
      {world, id} = Mobj.spawn(world, type, {source.x, source.y, source.z + 32})
      info = ElixirDoom.Info.thing(type)
      world = World.sound(world, info.see_sound, source)
      angle = Mobj.angle_to(source, dest)

      {spread, world} =
        if Mobj.flag?(dest, :shadow), do: World.random_spread(world), else: {0, world}

      angle = angle + spread * :math.pi() / 2048
      speed = info.speed
      travel = max(Mobj.approx_distance(source, dest) / speed, 1)

      world =
        World.update_mobj(world, id, fn m ->
          %{
            m
            | target: source_id,
              angle: angle,
              momx: speed * :math.cos(angle),
              momy: speed * :math.sin(angle),
              momz: (dest.z - source.z) / travel
          }
        end)

      launch(world, id)
    else
      _missing -> world
    end
  end

  @doc "A missile of `type` fired by player thing `source_id`, aimed up or down at whatever is ahead."
  @spec player_missile(World.t(), term(), atom()) :: World.t()
  def player_missile(world, source_id, type) do
    source = World.mobj(world, source_id)
    {slope, angle} = auto_aim(world, source_id, source.angle)
    {world, id} = Mobj.spawn(world, type, {source.x, source.y, source.z + 32})
    info = ElixirDoom.Info.thing(type)
    world = World.sound(world, info.see_sound, source)
    speed = info.speed

    world =
      World.update_mobj(world, id, fn m ->
        %{
          m
          | target: source_id,
            angle: angle,
            momx: speed * :math.cos(angle),
            momy: speed * :math.sin(angle),
            momz: speed * slope
        }
      end)

    launch(world, id)
  end

  @doc "The slope and angle a player's shot takes along `angle`: the nearest target within a few degrees."
  @spec auto_aim(World.t(), term(), number()) :: {float(), float()}
  def auto_aim(world, source_id, angle) do
    nudge = :math.pi() / 32

    Enum.find_value([angle, angle + nudge, angle - nudge], {0.0, angle}, fn try_angle ->
      case aim(world, source_id, try_angle, 1024.0) do
        {slope, id} when id != nil -> {slope, try_angle}
        _missed -> nil
      end
    end)
  end

  defp launch(world, id) do
    {roll, world} = World.random(world)

    world =
      World.update_mobj(world, id, fn m -> %{m | tics: max(1, m.tics - Bitwise.band(roll, 3))} end)

    missile = World.mobj(world, id)
    point = {missile.x + missile.momx / 2, missile.y + missile.momy / 2}
    world = World.update_mobj(world, id, &%{&1 | z: &1.z + &1.momz / 2})

    case Mobj.try_move(world, id, point) do
      {:ok, world} -> world
      {:blocked, world, _why} -> Mobj.explode_missile(world, id)
    end
  end

  @doc "A blast at thing `spot_id` hurting everything in sight of it within `damage` units."
  @spec radius_attack(World.t(), term(), term() | nil, number()) :: World.t()
  def radius_attack(world, spot_id, source_id, damage) do
    spot = World.mobj(world, spot_id)
    physics = World.physics(world)

    world.mobjs
    |> Map.values()
    |> Enum.filter(&Mobj.flag?(&1, :shootable))
    |> Enum.reject(&(&1.type in [:mt_cyborg, :mt_spider]))
    |> Enum.reduce(world, fn thing, acc ->
      distance = max(max(abs(thing.x - spot.x), abs(thing.y - spot.y)) - thing.radius, 0)

      if distance < damage and Sight.visible?(physics, {spot.x, spot.y, spot.z + 1}, thing),
        do: damage(acc, thing.id, spot_id, source_id, damage - distance),
        else: acc
    end)
  end

  @doc """
  A BFG ball bursting at thing `ball_id`: forty rays fan out across a quarter turn from
  the player who fired it, each hurting the first thing it finds and leaving a flash on it.
  """
  @spec bfg_spray(World.t(), term()) :: World.t()
  def bfg_spray(world, ball_id) do
    ball = World.mobj(world, ball_id)

    case ball && ball.target && World.mobj(world, ball.target) do
      %{} = shooter ->
        Enum.reduce(
          0..39,
          world,
          &spray_ray(&2, shooter, ball.angle - :math.pi() / 4 + :math.pi() / 2 / 40 * &1)
        )

      _gone ->
        world
    end
  end

  defp spray_ray(world, shooter, angle) do
    case aim(world, shooter.id, angle, 1024.0) do
      {_slope, nil} -> world
      {_slope, target_id} -> spray_hit(world, shooter, World.mobj(world, target_id))
    end
  end

  defp spray_hit(world, shooter, target) do
    {world, _flash} =
      Mobj.spawn(world, :mt_extrabfg, {target.x, target.y, target.z + target.height / 4})

    {damage, world} =
      Enum.reduce(1..15, {0, world}, fn _roll, {sum, acc} ->
        {roll, acc} = World.random(acc)
        {sum + Bitwise.band(roll, 7) + 1, acc}
      end)

    damage(world, target.id, shooter.id, shooter.id, damage)
  end

  @doc "Whether thing `a` can see thing `b`."
  @spec sees?(World.t(), map(), map()) :: boolean()
  def sees?(world, a, b) do
    eye = a.z + a.height - a.height / 4
    reject = if world.map.reject, do: {world.map.reject, tuple_size(world.map.sectors)}
    Sight.visible?(World.physics(world), {a.x, a.y, eye}, b, reject: reject)
  end
end
