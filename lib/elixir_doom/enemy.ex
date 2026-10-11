defmodule ElixirDoom.Enemy do
  @moduledoc """
  What monsters do in their states: wait and listen, chase, close in and attack, and cry
  out when hurt or killed.

  Each function takes the world and the id of the thing acting and gives the world back;
  `ElixirDoom.Actions` calls them by the action names in the state table.
  """

  alias Cauldron2D.Sectors.Noise
  alias Cauldron2D.Steer
  alias ElixirDoom.{Combat, Mobj, Specials, World}

  @eighth :math.pi() / 4
  @skull_speed 20.0
  @bosses %{
    {"E1M8", :mt_bruiser} => :floor,
    {"E2M8", :mt_cyborg} => :exit,
    {"E3M8", :mt_spider} => :exit,
    {"E4M6", :mt_cyborg} => :doors,
    {"E4M8", :mt_spider} => :floor
  }

  @doc "Stand and look and listen for a player; wake to chase one."
  @spec look(World.t(), term()) :: World.t()
  def look(world, id) do
    actor = World.mobj(world, id)
    actor = %{actor | threshold: 0}
    world = World.put_mobj(world, actor)

    case heard(world, actor) || look_for_player(world, actor, false) do
      nil ->
        world

      target_id ->
        world
        |> World.update_mobj(id, &%{&1 | target: target_id})
        |> see(id)
    end
  end

  defp heard(world, actor) do
    with id when id != nil <- Map.get(world.targets, actor.sector),
         %{health: health} = noise when health > 0 <- World.mobj(world, id),
         true <- Mobj.flag?(noise, :shootable),
         true <- not Mobj.flag?(actor, :ambush) or Combat.sees?(world, actor, noise) do
      noise.id
    else
      _nothing -> nil
    end
  end

  defp see(world, id) do
    actor = World.mobj(world, id)
    info = Mobj.info(actor)
    {world, sound} = see_sound(world, info.see_sound)

    world =
      if actor.type in [:mt_spider, :mt_cyborg],
        do: World.sound(world, sound, nil),
        else: World.sound(world, sound, actor)

    Mobj.set_state(world, id, info.see)
  end

  defp see_sound(world, sound) when sound in ["DSPOSIT1", "DSPOSIT2", "DSPOSIT3"] do
    {roll, world} = World.random(world)
    {world, "DSPOSIT#{rem(roll, 3) + 1}"}
  end

  defp see_sound(world, sound) when sound in ["DSBGSIT1", "DSBGSIT2"] do
    {roll, world} = World.random(world)
    {world, "DSBGSIT#{rem(roll, 2) + 1}"}
  end

  defp see_sound(world, sound), do: {world, sound}

  defp look_for_player(world, actor, all_around?) do
    world.players
    |> Map.values()
    |> Enum.map(&World.mobj(world, &1.mobj))
    |> Enum.reject(&is_nil/1)
    |> Enum.find_value(fn player ->
      cond do
        player.health <= 0 ->
          nil

        not Combat.sees?(world, actor, player) ->
          nil

        all_around? ->
          player.id

        in_front?(actor, player) or
            Mobj.approx_distance(actor, player) <= World.tuning(world, :melee_range) ->
          player.id

        true ->
          nil
      end
    end)
  end

  defp in_front?(actor, target) do
    difference = normal(Mobj.angle_to(actor, target) - actor.angle)
    difference <= :math.pi() / 2 or difference >= 3 * :math.pi() / 2
  end

  defp normal(angle) do
    turn = 2 * :math.pi()
    angle - turn * Float.floor(angle / turn)
  end

  @doc "Chase the target: turn to the way it is going, attack when it can, step on."
  @spec chase(World.t(), term()) :: World.t()
  def chase(world, id) do
    actor = World.mobj(world, id)
    actor = %{actor | reaction: max(actor.reaction - 1, 0)}
    actor = settle_threshold(world, actor)
    actor = turn_to_direction(actor)
    world = World.put_mobj(world, actor)
    target = actor.target && World.mobj(world, actor.target)

    cond do
      target == nil or not Mobj.flag?(target, :shootable) ->
        lost_target(world, actor)

      Mobj.flag?(actor, :justattacked) ->
        after_attack(world, actor)

      Mobj.info(actor).melee != nil and melee_range?(world, actor, target) ->
        world
        |> World.sound(Mobj.info(actor).attack_sound, actor)
        |> Mobj.set_state(id, Mobj.info(actor).melee)

      true ->
        missile_or_walk(world, actor, target)
    end
  end

  defp lost_target(world, actor) do
    case look_for_player(world, actor, true) do
      nil -> Mobj.set_state(world, actor.id, Mobj.info(actor).spawn)
      target_id -> World.put_mobj(world, %{actor | target: target_id})
    end
  end

  defp after_attack(world, actor) do
    world = World.put_mobj(world, Mobj.flag(actor, :justattacked, false))
    if world.skill == 5, do: world, else: new_chase_direction(world, actor.id)
  end

  defp settle_threshold(world, actor) do
    cond do
      actor.threshold == 0 ->
        actor

      actor.target == nil or (World.mobj(world, actor.target) || %{health: 0}).health <= 0 ->
        %{actor | threshold: 0}

      true ->
        %{actor | threshold: actor.threshold - 1}
    end
  end

  defp turn_to_direction(%{move_dir: nil} = actor), do: actor

  defp turn_to_direction(actor) do
    snapped = Float.floor(normal(actor.angle) / @eighth + 1.0e-9) * @eighth
    delta = normal(snapped - actor.move_dir * @eighth)

    cond do
      delta < 1.0e-6 or delta > 2 * :math.pi() - 1.0e-6 -> %{actor | angle: snapped}
      delta < :math.pi() -> %{actor | angle: snapped - @eighth}
      true -> %{actor | angle: snapped + @eighth}
    end
  end

  defp missile_or_walk(world, actor, target) do
    info = Mobj.info(actor)

    {fire?, world} =
      if info.missile != nil and not (world.skill < 5 and actor.move_count > 0),
        do: missile_range?(world, actor, target),
        else: {false, world}

    if fire? do
      world
      |> World.put_mobj(Mobj.flag(actor, :justattacked, true))
      |> Mobj.set_state(actor.id, info.missile)
    else
      walk_on(world, actor)
    end
  end

  defp walk_on(world, actor) do
    actor = %{actor | move_count: actor.move_count - 1}
    world = World.put_mobj(world, actor)

    world =
      if actor.move_count < 0 do
        new_chase_direction(world, actor.id)
      else
        case step(world, actor.id) do
          {:ok, world} -> world
          {:blocked, world} -> new_chase_direction(world, actor.id)
        end
      end

    {roll, world} = World.random(world)
    active = Mobj.info(actor).active_sound

    if active != nil and roll < 3,
      do: World.sound(world, active, World.mobj(world, actor.id)),
      else: world
  end

  defp melee_range?(world, actor, target) do
    reach = World.tuning(world, :melee_range) - 20 + Mobj.info(target).radius
    Mobj.approx_distance(actor, target) < reach and Combat.sees?(world, actor, target)
  end

  defp missile_range?(world, actor, target) do
    cond do
      not Combat.sees?(world, actor, target) ->
        {false, world}

      Mobj.flag?(actor, :justhit) ->
        {true, World.put_mobj(world, Mobj.flag(actor, :justhit, false))}

      actor.reaction > 0 ->
        {false, world}

      true ->
        distance = Mobj.approx_distance(actor, target) - 64
        distance = if Mobj.info(actor).melee == nil, do: distance - 128, else: distance

        distance =
          if actor.type in [:mt_skull, :mt_cyborg, :mt_spider], do: distance / 2, else: distance

        distance = if actor.type == :mt_cyborg, do: min(distance, 160), else: min(distance, 200)
        {roll, world} = World.random(world)
        {roll >= distance, world}
    end
  end

  defp new_chase_direction(world, id) do
    actor = World.mobj(world, id)

    case actor.target && World.mobj(world, actor.target) do
      nil -> world
      target -> steer_toward(world, actor, target)
    end
  end

  defp steer_toward(world, actor, target) do
    {direction, world} =
      Steer.chase(
        world,
        actor.move_dir,
        {target.x - actor.x, target.y - actor.y},
        &try_walk(&1, actor.id, &2),
        &World.random/1
      )

    World.update_mobj(world, actor.id, &%{&1 | move_dir: direction})
  end

  defp try_walk(world, id, direction) do
    world = World.update_mobj(world, id, &%{&1 | move_dir: direction})

    case step(world, id) do
      {:ok, world} ->
        {roll, world} = World.random(world)
        {:ok, World.update_mobj(world, id, &%{&1 | move_count: Bitwise.band(roll, 15)})}

      {:blocked, world} ->
        {:blocked, world}
    end
  end

  defp step(world, id) do
    actor = World.mobj(world, id)

    if actor.move_dir == nil do
      {:blocked, world}
    else
      {dx, dy} = Steer.vector(actor.move_dir)
      speed = Mobj.info(actor).speed

      case Mobj.try_move(world, id, {actor.x + dx * speed, actor.y + dy * speed}) do
        {:ok, world} ->
          {:ok, World.update_mobj(world, id, &settle_on_floor/1)}

        {:blocked, world, why} ->
          blocked_step(world, id, why)
      end
    end
  end

  defp settle_on_floor(actor) do
    actor = Mobj.flag(actor, :infloat, false)
    if Mobj.flag?(actor, :float), do: actor, else: %{actor | z: actor.floor}
  end

  defp blocked_step(world, id, why) do
    actor = World.mobj(world, id)

    if Mobj.flag?(actor, :float) and why.floats? do
      z = if actor.z < why.place.floor, do: actor.z + 4.0, else: actor.z - 4.0
      {:ok, World.put_mobj(world, Mobj.flag(%{actor | z: z}, :infloat, true))}
    else
      {world, used?} = open_doors(world, id, why.place.lines)
      world = World.update_mobj(world, id, &%{&1 | move_dir: nil})
      if used?, do: {:ok, world}, else: {:blocked, world}
    end
  end

  defp open_doors(world, id, lines) do
    Enum.reduce(lines, {world, false}, fn line, {acc, any?} ->
      case Specials.use_line(acc, id, line, 0) do
        {:used, acc} -> {acc, true}
        {:unused, acc} -> {acc, any?}
      end
    end)
  end

  @doc "Turn to face the target, a little off where it is hard to see."
  @spec face_target(World.t(), term()) :: World.t()
  def face_target(world, id) do
    actor = World.mobj(world, id)

    case actor.target && World.mobj(world, actor.target) do
      nil ->
        world

      target ->
        actor = %{Mobj.flag(actor, :ambush, false) | angle: Mobj.angle_to(actor, target)}

        if Mobj.flag?(target, :shadow) do
          {spread, world} = World.random_spread(world)
          World.put_mobj(world, %{actor | angle: actor.angle + spread * :math.pi() / 1024})
        else
          World.put_mobj(world, actor)
        end
    end
  end

  @doc "A zombie's pistol shot."
  @spec pistol(World.t(), term()) :: World.t()
  def pistol(world, id), do: bullets(world, id, 1, "DSPISTOL")

  @doc "A sergeant's shotgun blast."
  @spec shotgun(World.t(), term()) :: World.t()
  def shotgun(world, id), do: bullets(world, id, 3, "DSSHOTGN")

  @doc "A heavy weapon dude's chaingun burst."
  @spec chaingun(World.t(), term()) :: World.t()
  def chaingun(world, id), do: bullets(world, id, 1, "DSSHOTGN")

  defp bullets(world, id, count, sound) do
    world = face_target(world, id)

    case World.mobj(world, id) do
      %{target: target} = actor when target != nil ->
        range = World.tuning(world, :missile_range)
        {slope, _hit} = Combat.aim(world, id, actor.angle, range)
        world = World.sound(world, sound, actor)

        Enum.reduce(1..count, world, fn _pellet, acc ->
          {spread, acc} = World.random_spread(acc)
          {roll, acc} = World.random(acc)
          damage = (rem(roll, 5) + 1) * 3

          Combat.line_attack(
            acc,
            id,
            actor.angle + spread * :math.pi() / 2048,
            range,
            slope,
            damage
          )
        end)

      _no_target ->
        world
    end
  end

  @doc "An imp's claw or fireball."
  @spec imp(World.t(), term()) :: World.t()
  def imp(world, id), do: claw_or_missile(world, id, 8, 3, "DSCLAW", :mt_troopshot)

  @doc "A demon's bite."
  @spec bite(World.t(), term()) :: World.t()
  def bite(world, id), do: claw_or_missile(world, id, 10, 4, nil, nil)

  @doc "A cacodemon's bite or ball."
  @spec caco(World.t(), term()) :: World.t()
  def caco(world, id), do: claw_or_missile(world, id, 6, 10, nil, :mt_headshot)

  @doc "A baron's claw or ball."
  @spec baron(World.t(), term()) :: World.t()
  def baron(world, id), do: claw_or_missile(world, id, 8, 10, "DSCLAW", :mt_bruisershot)

  defp claw_or_missile(world, id, sides, scale, sound, missile) do
    world = face_target(world, id)
    actor = World.mobj(world, id)

    case actor.target && World.mobj(world, actor.target) do
      nil ->
        world

      target ->
        if melee_range?(world, actor, target),
          do: claw(world, actor, target, {sides, scale, sound}),
          else: throw_missile(world, id, target, missile)
    end
  end

  defp claw(world, actor, target, {sides, scale, sound}) do
    {roll, world} = World.random(world)
    world = World.sound(world, sound, actor)
    Combat.damage(world, target.id, actor.id, actor.id, (rem(roll, sides) + 1) * scale)
  end

  defp throw_missile(world, _id, _target, nil), do: world

  defp throw_missile(world, id, target, missile),
    do: Combat.missile(world, id, target.id, missile)

  @doc "A Cyberdemon fires a rocket at its target."
  @spec rocket(World.t(), term()) :: World.t()
  def rocket(world, id) do
    world = face_target(world, id)

    case World.mobj(world, id) do
      %{target: target} when target != nil -> Combat.missile(world, id, target, :mt_rocket)
      _none -> world
    end
  end

  @doc "A step that makes a sound, `name`, then the chase goes on."
  @spec stomp(World.t(), term(), String.t()) :: World.t()
  def stomp(world, id, name), do: world |> World.sound(name, World.mobj(world, id)) |> chase(id)

  @doc """
  After a burst, keep firing while the target is alive and in sight; give up now and then
  less often than one time in `chance` out of 256.
  """
  @spec refire(World.t(), term(), 0..255) :: World.t()
  def refire(world, id, chance) do
    world = face_target(world, id)
    {roll, world} = World.random(world)
    actor = World.mobj(world, id)
    target = actor.target && World.mobj(world, actor.target)

    cond do
      roll < chance ->
        world

      target == nil or target.health <= 0 or not Combat.sees?(world, actor, target) ->
        Mobj.set_state(world, id, Mobj.info(actor).see)

      true ->
        world
    end
  end

  @doc "A lost soul hurls itself at its target."
  @spec charge(World.t(), term()) :: World.t()
  def charge(world, id) do
    actor = World.mobj(world, id)

    case actor.target && World.mobj(world, actor.target) do
      nil ->
        world

      target ->
        world = World.sound(world, Mobj.info(actor).attack_sound, actor)
        world = face_target(world, id)
        actor = World.mobj(world, id)
        travel = max(Mobj.approx_distance(actor, target) / @skull_speed, 1)

        World.put_mobj(world, %{
          Mobj.flag(actor, :skullfly, true)
          | momx: @skull_speed * :math.cos(actor.angle),
            momy: @skull_speed * :math.sin(actor.angle),
            momz: (target.z + target.height / 2 - actor.z) / travel
        })
    end
  end

  @doc "The pain cry."
  @spec pain(World.t(), term()) :: World.t()
  def pain(world, id) do
    actor = World.mobj(world, id)
    World.sound(world, Mobj.info(actor).pain_sound, actor)
  end

  @doc "The death cry."
  @spec scream(World.t(), term()) :: World.t()
  def scream(world, id) do
    actor = World.mobj(world, id)
    {world, sound} = death_sound(world, Mobj.info(actor).death_sound)
    at = if actor.type in [:mt_spider, :mt_cyborg], do: nil, else: actor
    World.sound(world, sound, at)
  end

  defp death_sound(world, sound) when sound in ["DSPODTH1", "DSPODTH2", "DSPODTH3"] do
    {roll, world} = World.random(world)
    {world, "DSPODTH#{rem(roll, 3) + 1}"}
  end

  defp death_sound(world, sound) when sound in ["DSBGDTH1", "DSBGDTH2"] do
    {roll, world} = World.random(world)
    {world, "DSBGDTH#{rem(roll, 2) + 1}"}
  end

  defp death_sound(world, sound), do: {world, sound}

  @doc "The sound of being torn apart."
  @spec slop(World.t(), term()) :: World.t()
  def slop(world, id), do: World.sound(world, "DSSLOP", World.mobj(world, id))

  @doc "A body stops blocking."
  @spec fall(World.t(), term()) :: World.t()
  def fall(world, id), do: World.update_mobj(world, id, &Mobj.flag(&1, :solid, false))

  @doc "A blast of 128 at the thing, credited to whatever set it off."
  @spec explode(World.t(), term()) :: World.t()
  def explode(world, id) do
    actor = World.mobj(world, id)
    Combat.radius_attack(world, id, actor.target, 128)
  end

  @doc "When the last baron of E1M8 dies, the floor tagged 666 lowers."
  @spec boss_death(World.t(), term()) :: World.t()
  def boss_death(world, id) do
    actor = World.mobj(world, id)

    alive? =
      world.mobjs
      |> Map.values()
      |> Enum.any?(&(&1.id != id and &1.type == actor.type and &1.health > 0))

    players_alive? =
      world.players
      |> Map.values()
      |> Enum.any?(&((World.mobj(world, &1.mobj) || %{health: 0}).health > 0))

    if alive? or not players_alive?,
      do: world,
      else: boss_falls(world, Map.get(@bosses, {world.level, actor.type}))
  end

  defp boss_falls(world, nil), do: world
  defp boss_falls(world, :floor), do: Specials.floor_by_tag(world, 666, :lower_to_lowest)
  defp boss_falls(world, :doors), do: Specials.doors_by_tag(world, 666, :blaze_open)
  defp boss_falls(world, :exit), do: %{world | exit: :normal}

  @doc "A sound made by thing `id` wakes the monsters within earshot of it."
  @spec alert(World.t(), term()) :: World.t()
  def alert(world, id) do
    case World.mobj(world, id) do
      nil ->
        world

      emitter ->
        reached =
          Noise.spread(%{map: world.map, sectors: world.sectors}, world.noise, emitter.sector)

        %{world | targets: Enum.reduce(Map.keys(reached), world.targets, &Map.put(&2, &1, id))}
    end
  end
end
