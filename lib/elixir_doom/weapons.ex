defmodule ElixirDoom.Weapons do
  @moduledoc """
  The weapon a player holds: the two pictures drawn over the view — the weapon and its
  muzzle flash — each running through its own states, raising, lowering, readying and
  firing, and what each weapon does when it fires.

  `tick/2` runs one tic of player `id`'s weapon. The pictures' positions, `sx` and `sy`,
  are in Doom's 320 by 200 screen: the weapon is up at `32` and down at `128`.
  """

  alias Cauldron2D.States
  alias ElixirDoom.{Combat, Enemy, Info, Mobj, Player, Tables, World}

  @top 32.0
  @bottom 128.0

  @doc "Whether `player` has the ammunition to fire `weapon`."
  @spec has_ammo?(map(), atom()) :: boolean()
  def has_ammo?(player, weapon) do
    case Tables.weapon(weapon).ammo do
      nil -> true
      ammo -> Map.get(player.ammo, ammo, 0) >= needed(weapon)
    end
  end

  defp needed(:bfg), do: 40
  defp needed(_weapon), do: 1

  @doc "Raise player `id`'s pending weapon, or the one in hand."
  @spec bring_up(World.t(), term()) :: World.t()
  def bring_up(world, id) do
    player = Player.get(world, id)
    weapon = player.pending || player.ready

    world =
      if weapon == :chainsaw,
        do: World.sound(world, "DSSAWUP", World.mobj(world, player.mobj)),
        else: world

    world
    |> Player.update(id, &%{&1 | ready: weapon, pending: nil, weapon: %{&1.weapon | sy: @bottom}})
    |> set(id, :weapon, Tables.weapon(weapon).up)
  end

  @doc "Lower player `id`'s weapon, as when they die."
  @spec drop(World.t(), term()) :: World.t()
  def drop(world, id),
    do: set(world, id, :weapon, Tables.weapon(Player.get(world, id).ready).down)

  @doc "One tic of player `id`'s weapon and flash."
  @spec tick(World.t(), term()) :: World.t()
  def tick(world, id) do
    world
    |> tick_sprite(id, :weapon)
    |> tick_sprite(id, :flash)
    |> Player.update(id, &%{&1 | flash: %{&1.flash | sx: &1.weapon.sx, sy: &1.weapon.sy}})
  end

  defp tick_sprite(world, id, slot) do
    player = Player.get(world, id)
    sprite = Map.fetch!(player, slot)

    cond do
      sprite.state == nil -> world
      sprite.tics == -1 -> world
      sprite.tics - 1 <= 0 -> set(world, id, slot, Info.state(sprite.state).next)
      true -> Player.update(world, id, &Map.put(&1, slot, %{sprite | tics: sprite.tics - 1}))
    end
  end

  @doc "Put player `id`'s `slot` (`:weapon` or `:flash`) into `state`, running its actions."
  @spec set(World.t(), term(), :weapon | :flash, atom() | nil) :: World.t()
  def set(world, id, slot, state) do
    sprite = Map.fetch!(Player.get(world, id), slot)

    actor = %{
      state: sprite.state,
      tics: sprite.tics,
      picture: nil,
      world: world,
      id: id,
      slot: slot
    }

    actor
    |> States.enter(Info.states(), state, &act/2)
    |> then(fn actor -> store(actor.world, id, slot, actor.state, actor.tics) end)
  end

  defp act(actor, action) do
    world = store(actor.world, actor.id, actor.slot, actor.state, actor.tics)
    world = run(world, actor.id, actor.slot, action)
    sprite = Map.fetch!(Player.get(world, actor.id), actor.slot)
    %{actor | world: world, state: sprite.state, tics: sprite.tics}
  end

  defp store(world, id, slot, state, tics),
    do:
      Player.update(
        world,
        id,
        &Map.put(&1, slot, %{Map.fetch!(&1, slot) | state: state, tics: tics})
      )

  defp run(world, id, _slot, :a_weaponready), do: ready(world, id)
  defp run(world, id, _slot, :a_refire), do: refire(world, id)
  defp run(world, id, _slot, :a_checkreload), do: check_ammo(world, id) |> elem(1)
  defp run(world, id, _slot, :a_lower), do: lower(world, id)
  defp run(world, id, _slot, :a_raise), do: raise_weapon(world, id)
  defp run(world, id, _slot, :a_gunflash), do: flash(world, id)
  defp run(world, id, _slot, :a_punch), do: punch(world, id)
  defp run(world, id, _slot, :a_saw), do: saw(world, id)
  defp run(world, id, _slot, :a_firepistol), do: pistol(world, id)
  defp run(world, id, _slot, :a_fireshotgun), do: shotgun(world, id)
  defp run(world, id, _slot, :a_firecgun), do: chaingun(world, id)
  defp run(world, id, _slot, :a_firemissile), do: missile(world, id, :mt_rocket)
  defp run(world, id, _slot, :a_fireplasma), do: plasma(world, id)
  defp run(world, id, _slot, :a_bfgsound), do: World.sound(world, "DSBFG", own(world, id))
  defp run(world, id, _slot, :a_firebfg), do: bfg(world, id)
  defp run(world, id, _slot, :a_light0), do: Player.update(world, id, &%{&1 | extra_light: 0})
  defp run(world, id, _slot, :a_light1), do: Player.update(world, id, &%{&1 | extra_light: 1})
  defp run(world, id, _slot, :a_light2), do: Player.update(world, id, &%{&1 | extra_light: 2})
  defp run(world, _id, _slot, _action), do: world

  defp own(world, id), do: World.mobj(world, Player.get(world, id).mobj)

  defp ready(world, id) do
    player = Player.get(world, id)
    mobj = own(world, id)

    world =
      world
      |> settle_body(mobj)
      |> saw_idle(player, mobj)

    cond do
      player.pending != nil or player.health <= 0 ->
        set(world, id, :weapon, Tables.weapon(player.ready).down)

      trigger?(player) ->
        world |> Player.update(id, &%{&1 | attack_down: true}) |> fire(id)

      true ->
        world |> release_trigger(id, player) |> sway(id)
    end
  end

  defp settle_body(world, %{state: state} = mobj) when state in [:s_play_atk1, :s_play_atk2],
    do: Mobj.set_state(world, mobj.id, :s_play)

  defp settle_body(world, _mobj), do: world

  defp saw_idle(world, %{ready: :chainsaw, weapon: %{state: :s_saw}}, mobj),
    do: World.sound(world, "DSSAWIDL", mobj)

  defp saw_idle(world, _player, _mobj), do: world

  defp trigger?(player),
    do:
      MapSet.member?(player.held, :fire) and
        (not player.attack_down or player.ready not in [:missile, :bfg])

  defp release_trigger(world, id, player) do
    if MapSet.member?(player.held, :fire),
      do: world,
      else: Player.update(world, id, &%{&1 | attack_down: false})
  end

  defp sway(world, id) do
    player = Player.get(world, id)
    phase = 2 * :math.pi() * rem(world.tic * 128, 8192) / 8192
    half = 2 * :math.pi() * rem(world.tic * 128, 4096) / 8192

    Player.update(world, id, fn p ->
      %{
        p
        | weapon: %{
            p.weapon
            | sx: 1 + player.bob * :math.cos(phase),
              sy: @top + player.bob * :math.sin(half)
          }
      }
    end)
  end

  defp fire(world, id) do
    case check_ammo(world, id) do
      {false, world} ->
        world

      {true, world} ->
        player = Player.get(world, id)
        mobj = own(world, id)

        world
        |> Mobj.set_state(mobj.id, :s_play_atk1)
        |> set(id, :weapon, Tables.weapon(player.ready).attack)
        |> Enemy.alert(mobj.id)
    end
  end

  defp check_ammo(world, id) do
    player = Player.get(world, id)

    if has_ammo?(player, player.ready) do
      {true, world}
    else
      choice =
        Enum.find(
          [:plasma, :chaingun, :shotgun, :pistol, :chainsaw, :missile, :bfg, :fist],
          fn weapon ->
            MapSet.member?(player.weapons, weapon) and has_ammo?(player, weapon)
          end
        )

      world =
        world
        |> Player.update(id, &%{&1 | pending: choice})
        |> set(id, :weapon, Tables.weapon(player.ready).down)

      {false, world}
    end
  end

  defp refire(world, id) do
    player = Player.get(world, id)

    if MapSet.member?(player.held, :fire) and player.pending == nil and player.health > 0 do
      world |> Player.update(id, &%{&1 | refire: &1.refire + 1}) |> fire(id)
    else
      world |> Player.update(id, &%{&1 | refire: 0}) |> check_ammo(id) |> elem(1)
    end
  end

  defp lower(world, id) do
    speed = World.tuning(world, :weapon_speed)
    world = Player.update(world, id, &%{&1 | weapon: %{&1.weapon | sy: &1.weapon.sy + speed}})
    player = Player.get(world, id)

    cond do
      player.weapon.sy < @bottom ->
        world

      player.status == :dead ->
        Player.update(world, id, &%{&1 | weapon: %{&1.weapon | sy: @bottom}})

      player.health <= 0 ->
        store(world, id, :weapon, nil, -1)

      true ->
        world |> Player.update(id, &%{&1 | ready: &1.pending || &1.ready}) |> bring_up(id)
    end
  end

  defp raise_weapon(world, id) do
    speed = World.tuning(world, :weapon_speed)
    world = Player.update(world, id, &%{&1 | weapon: %{&1.weapon | sy: &1.weapon.sy - speed}})
    player = Player.get(world, id)

    if player.weapon.sy > @top do
      world
    else
      world
      |> Player.update(id, &%{&1 | weapon: %{&1.weapon | sy: @top}})
      |> set(id, :weapon, Tables.weapon(player.ready).ready)
    end
  end

  defp flash(world, id) do
    player = Player.get(world, id)

    world
    |> Mobj.set_state(player.mobj, :s_play_atk2)
    |> set(id, :flash, Tables.weapon(player.ready).flash)
  end

  defp spend(world, id, count \\ 1) do
    player = Player.get(world, id)

    case Tables.weapon(player.ready).ammo do
      nil ->
        world

      ammo ->
        Player.update(
          world,
          id,
          &%{&1 | ammo: Map.update!(&1.ammo, ammo, fn have -> max(have - count, 0) end)}
        )
    end
  end

  defp punch(world, id) do
    mobj = own(world, id)
    player = Player.get(world, id)
    {roll, world} = World.random(world)
    damage = (rem(roll, 10) + 1) * 2
    damage = if Map.get(player.powers, :strength, 0) > 0, do: damage * 10, else: damage
    {spread, world} = World.random_spread(world)
    angle = mobj.angle + spread * :math.pi() / 8192
    range = World.tuning(world, :melee_range)
    {slope, target} = Combat.aim(world, mobj.id, angle, range)
    world = Combat.line_attack(world, mobj.id, angle, range, slope, damage)

    case target && World.mobj(world, target) do
      %{} = hit ->
        world
        |> World.sound("DSPUNCH", mobj)
        |> World.update_mobj(mobj.id, &%{&1 | angle: Mobj.angle_to(&1, hit)})

      _miss ->
        world
    end
  end

  defp saw(world, id) do
    mobj = own(world, id)
    {roll, world} = World.random(world)
    damage = 2 * (rem(roll, 10) + 1)
    {spread, world} = World.random_spread(world)
    angle = mobj.angle + spread * :math.pi() / 8192
    range = World.tuning(world, :melee_range) + 1
    {slope, target} = Combat.aim(world, mobj.id, angle, range)
    world = Combat.line_attack(world, mobj.id, angle, range, slope, damage)

    case target && World.mobj(world, target) do
      %{} = hit ->
        world
        |> World.sound("DSSAWHIT", mobj)
        |> World.update_mobj(mobj.id, &%{&1 | angle: Mobj.angle_to(&1, hit)})

      _miss ->
        World.sound(world, "DSSAWFUL", mobj)
    end
  end

  defp pistol(world, id) do
    mobj = own(world, id)
    player = Player.get(world, id)

    world
    |> World.sound("DSPISTOL", mobj)
    |> Mobj.set_state(mobj.id, :s_play_atk2)
    |> spend(id)
    |> set(id, :flash, Tables.weapon(:pistol).flash)
    |> shots(id, 1, player.refire == 0)
  end

  defp shotgun(world, id) do
    mobj = own(world, id)

    world
    |> World.sound("DSSHOTGN", mobj)
    |> Mobj.set_state(mobj.id, :s_play_atk2)
    |> spend(id)
    |> set(id, :flash, Tables.weapon(:shotgun).flash)
    |> shots(id, 7, false)
  end

  defp chaingun(world, id) do
    player = Player.get(world, id)

    if Map.get(player.ammo, :clip, 0) <= 0 do
      world
    else
      mobj = own(world, id)
      flash = if player.weapon.state == :s_chain2, do: :s_chainflash2, else: :s_chainflash1

      world
      |> World.sound("DSPISTOL", mobj)
      |> Mobj.set_state(mobj.id, :s_play_atk2)
      |> spend(id)
      |> set(id, :flash, flash)
      |> shots(id, 1, player.refire == 0)
    end
  end

  defp shots(world, id, count, accurate?) do
    mobj = own(world, id)
    {slope, _angle} = Combat.auto_aim(world, mobj.id, mobj.angle)
    range = World.tuning(world, :missile_range)

    Enum.reduce(1..count, world, fn _shot, acc ->
      {roll, acc} = World.random(acc)
      damage = 5 * (rem(roll, 3) + 1)
      {spread, acc} = if accurate?, do: {0, acc}, else: World.random_spread(acc)

      Combat.line_attack(
        acc,
        mobj.id,
        mobj.angle + spread * :math.pi() / 8192,
        range,
        slope,
        damage
      )
    end)
  end

  defp missile(world, id, type) do
    world
    |> spend(id)
    |> Combat.player_missile(Player.get(world, id).mobj, type)
  end

  defp plasma(world, id) do
    {roll, world} = World.random(world)
    flash = if Bitwise.band(roll, 1) == 1, do: :s_plasmaflash2, else: :s_plasmaflash1

    world
    |> spend(id)
    |> set(id, :flash, flash)
    |> Combat.player_missile(Player.get(world, id).mobj, :mt_plasma)
  end

  defp bfg(world, id) do
    world
    |> spend(id, 40)
    |> Combat.player_missile(Player.get(world, id).mobj, :mt_bfg)
  end
end
