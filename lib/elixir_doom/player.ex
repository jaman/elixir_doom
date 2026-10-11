defmodule ElixirDoom.Player do
  @moduledoc """
  A player: what they carry, how their keys move them, how high their eye sits and bobs,
  reaching for switches and doors, taking damage through armour, and dying.

  A player's state lives in the world under their id and names the thing they move as
  (`mobj`). `think/2` runs one tic of it from the keys held: `:forward`, `:back`,
  `:turn_left`, `:turn_right`, `:strafe_left`, `:strafe_right`, `:run`, `:fire`, `:use`,
  `:next_weapon`, `:prev_weapon` and `:weapon_1`..`:weapon_7`. A movement or turn held
  through a stick moves or turns as far as the stick is pushed (the `strength` the input
  gives it).
  """

  alias Cauldron2D.Sectors.Map, as: SectorMap
  alias Cauldron2D.Sectors.{Move, Trace}
  alias ElixirDoom.{Combat, Mobj, Specials, Tables, Weapons, World}

  @slots %{
    weapon_1: 1,
    weapon_2: 2,
    weapon_3: 3,
    weapon_4: 4,
    weapon_5: 5,
    weapon_6: 6,
    weapon_7: 7
  }

  @doc "A player's starting state: a fist and a pistol with 50 bullets, 100 health."
  @spec fresh(term()) :: map()
  def fresh(id) do
    %{
      id: id,
      mobj: nil,
      held: MapSet.new(),
      strength: %{},
      previous: MapSet.new(),
      view_height: 41.0,
      delta_view: 0.0,
      view_z: 0.0,
      bob: 0.0,
      health: 100,
      armor: 0,
      armor_type: 0,
      powers: %{},
      cards: MapSet.new(),
      weapons: MapSet.new([:fist, :pistol]),
      ammo: %{clip: 50, shell: 0, cell: 0, misl: 0},
      max_ammo: Tables.max_ammo(),
      backpack: false,
      ready: :pistol,
      pending: nil,
      weapon: %{state: nil, tics: -1, sx: 1.0, sy: 128.0},
      flash: %{state: nil, tics: -1, sx: 1.0, sy: 128.0},
      attack_down: false,
      refire: 0,
      damage_count: 0,
      bonus_count: 0,
      attacker: nil,
      extra_light: 0,
      message: nil,
      message_tics: 0,
      status: :alive,
      turn_held: 0,
      face: %{tics: 0, look: 0}
    }
  end

  @doc "The player's state with everything that does not carry to a new life reset."
  @spec reborn(map()) :: map()
  def reborn(player),
    do: %{
      fresh(player.id)
      | held: player.held,
        strength: player.strength,
        previous: player.previous
    }

  @doc "The state of player `id`."
  @spec get(World.t(), term()) :: map() | nil
  def get(world, id), do: Map.get(world.players, id)

  @doc "Replace player `id`'s state with `fun.(player)`."
  @spec update(World.t(), term(), (map() -> map())) :: World.t()
  def update(world, id, fun) do
    case get(world, id) do
      nil -> world
      player -> %{world | players: Map.put(world.players, id, fun.(player))}
    end
  end

  @doc "Whether player `id` is holding a movement key."
  @spec pushing?(World.t(), term()) :: boolean()
  def pushing?(world, id) do
    case get(world, id) do
      nil ->
        false

      player ->
        Enum.any?(
          [:forward, :back, :strafe_left, :strafe_right],
          &MapSet.member?(player.held, &1)
        )
    end
  end

  @doc "Whether thing `source` is a player holding a running chainsaw."
  @spec sawing?(World.t(), map() | nil) :: boolean()
  def sawing?(_world, nil), do: false
  def sawing?(_world, %{player: nil}), do: false
  def sawing?(world, %{player: id}), do: (get(world, id) || %{ready: nil}).ready == :chainsaw

  @doc "Whether the action was pressed this tic."
  @spec pressed?(map(), atom()) :: boolean()
  def pressed?(player, action),
    do: MapSet.member?(player.held, action) and not MapSet.member?(player.previous, action)

  @doc "One tic of player `id`."
  @spec think(World.t(), term()) :: World.t()
  def think(world, id) do
    player = get(world, id)

    world =
      case player.status do
        :dead -> death_think(world, id)
        _alive -> live_think(world, id)
      end

    world
    |> update(id, &%{&1 | previous: &1.held})
    |> count_down(id)
  end

  defp live_think(world, id) do
    player = get(world, id)
    mobj = World.mobj(world, player.mobj)

    world =
      if mobj.reaction > 0,
        do: World.put_mobj(world, %{mobj | reaction: mobj.reaction - 1}),
        else: move(world, id)

    world
    |> calc_height(id)
    |> Specials.player_in_sector(id)
    |> change_weapon(id)
    |> use_pressed(id)
    |> Weapons.tick(id)
  end

  defp move(world, id) do
    player = get(world, id)
    mobj = World.mobj(world, player.mobj)
    run? = World.tuning(world, :always_run) != MapSet.member?(player.held, :run)
    {forward, side, turn, turn_held} = command(world, player, run?)
    angle = mobj.angle + turn
    on_ground? = mobj.z <= mobj.floor

    {momx, momy} =
      if on_ground?,
        do: thrust({mobj.momx, mobj.momy}, angle, forward, side),
        else: {mobj.momx, mobj.momy}

    world =
      world
      |> World.put_mobj(%{mobj | angle: angle, momx: momx, momy: momy})
      |> update(id, &%{&1 | turn_held: turn_held})

    if (forward != 0 or side != 0) and mobj.state == :s_play,
      do: Mobj.set_state(world, mobj.id, :s_play_run1),
      else: world
  end

  defp command(world, player, run?) do
    forward_speed = World.tuning(world, if(run?, do: :run, else: :walk))
    side_speed = World.tuning(world, if(run?, do: :strafe_run, else: :strafe_walk))
    forward = axis(player, :forward, :back) * forward_speed
    side = axis(player, :strafe_right, :strafe_left) * side_speed
    turning = axis(player, :turn_left, :turn_right)
    turn_held = if turning != 0, do: player.turn_held + 1, else: 0

    rate =
      cond do
        turn_held < World.tuning(world, :slow_turn_tics) -> World.tuning(world, :turn_slow)
        run? -> World.tuning(world, :turn_run)
        true -> World.tuning(world, :turn_walk)
      end

    {forward, side, turning * rate, turn_held}
  end

  defp axis(player, plus, minus), do: push(player, plus) - push(player, minus)

  defp push(player, action) do
    if MapSet.member?(player.held, action),
      do: Map.get(player.strength, action, 1),
      else: 0
  end

  defp thrust({momx, momy}, angle, forward, side) do
    side_angle = angle - :math.pi() / 2

    {momx + forward * :math.cos(angle) + side * :math.cos(side_angle),
     momy + forward * :math.sin(angle) + side * :math.sin(side_angle)}
  end

  defp calc_height(world, id) do
    player = get(world, id)
    mobj = World.mobj(world, player.mobj)
    view = World.tuning(world, :view_height)
    bob = min((mobj.momx * mobj.momx + mobj.momy * mobj.momy) / 4, World.tuning(world, :max_bob))

    if mobj.z > mobj.floor do
      view_z = min(mobj.z + view, mobj.ceiling - 4)
      update(world, id, &%{&1 | bob: bob, view_z: view_z})
    else
      wobble = bob / 2 * :math.sin(2 * :math.pi() * rem(world.tic, 20) / 20)

      {height, delta} =
        settle_view(
          player.view_height + player.delta_view,
          player.delta_view,
          view,
          player.status
        )

      view_z = min(mobj.z + height + wobble, mobj.ceiling - 4)
      update(world, id, &%{&1 | bob: bob, view_height: height, delta_view: delta, view_z: view_z})
    end
  end

  defp settle_view(height, delta, view, :alive) do
    {height, delta} = if height > view, do: {view, 0.0}, else: {height, delta}

    {height, delta} =
      if height < view / 2,
        do: {view / 2, if(delta <= 0, do: 1 / 65_536, else: delta)},
        else: {height, delta}

    delta =
      if delta != 0 do
        next = delta + 0.25
        if next == 0, do: 1 / 65_536, else: next
      else
        delta
      end

    {height, delta}
  end

  defp settle_view(height, delta, _view, _status), do: {height, delta}

  @doc "The eye drops as a player steps up onto `rise`, and comes back up over a few tics."
  @spec step_up(World.t(), term(), number()) :: World.t()
  def step_up(world, id, rise) do
    view = World.tuning(world, :view_height)

    update(world, id, fn player ->
      height = player.view_height - rise
      %{player | view_height: height, delta_view: (view - height) / 8}
    end)
  end

  @doc "The eye dips as a player lands hard."
  @spec squat(World.t(), term(), number()) :: World.t()
  def squat(world, id, delta), do: update(world, id, &%{&1 | delta_view: delta})

  defp change_weapon(world, id) do
    player = get(world, id)

    wanted =
      cond do
        slot =
            Enum.find_value(@slots, fn {action, slot} -> if pressed?(player, action), do: slot end) ->
          by_slot(player, slot)

        pressed?(player, :next_weapon) ->
          cycle(player, 1)

        pressed?(player, :prev_weapon) ->
          cycle(player, -1)

        true ->
          nil
      end

    if wanted != nil and wanted != player.ready and MapSet.member?(player.weapons, wanted),
      do: update(world, id, &%{&1 | pending: wanted}),
      else: world
  end

  defp by_slot(player, 1) do
    if MapSet.member?(player.weapons, :chainsaw) and
         not (player.ready == :chainsaw and Map.get(player.powers, :strength, 0) > 0),
       do: :chainsaw,
       else: :fist
  end

  defp by_slot(_player, slot) do
    Enum.find(
      Tables.weapon_order(),
      &(Tables.weapon(&1).slot == slot and &1 not in [:fist, :chainsaw])
    )
  end

  defp cycle(player, direction) do
    owned =
      Enum.filter(
        Tables.weapon_order(),
        &(MapSet.member?(player.weapons, &1) and Weapons.has_ammo?(player, &1))
      )

    index = Enum.find_index(owned, &(&1 == player.ready)) || 0
    Enum.at(owned, rem(index + direction + length(owned), max(length(owned), 1)))
  end

  defp use_pressed(world, id) do
    player = get(world, id)
    if pressed?(player, :use), do: use_lines(world, id), else: world
  end

  defp use_lines(world, id) do
    player = get(world, id)
    mobj = World.mobj(world, player.mobj)
    range = World.tuning(world, :use_range)
    to = {mobj.x + range * :math.cos(mobj.angle), mobj.y + range * :math.sin(mobj.angle)}

    world.map
    |> Trace.run(world.blockmap, {mobj.x, mobj.y}, to, bodies: false)
    |> Enum.reduce_while(world, fn %{line: index}, acc ->
      line = elem(acc.map.lines, index)

      cond do
        line.special != 0 ->
          {from_x, from_y} = SectorMap.vertex(acc.map, line.from)
          {to_x, to_y} = SectorMap.vertex(acc.map, line.to)

          side =
            SectorMap.point_side({mobj.x, mobj.y}, {from_x, from_y, to_x - from_x, to_y - from_y})

          {_used, acc} = Specials.use_line(acc, mobj.id, index, side)
          {:halt, acc}

        closed?(acc, index) ->
          {:halt, World.sound(acc, "DSNOWAY", mobj)}

        true ->
          {:cont, acc}
      end
    end)
  end

  defp closed?(world, index) do
    case Move.opening(World.physics(world), index) do
      nil -> true
      opening -> opening.range <= 0
    end
  end

  @doc """
  How much of `damage` gets past player `id`'s armour, and the world with the armour worn
  down: `{world, damage}`.
  """
  @spec absorb(World.t(), term(), number(), map() | nil) :: {World.t(), number()}
  def absorb(world, id, damage, _source) do
    player = get(world, id)

    cond do
      Map.get(player.powers, :invulnerability, 0) > 0 and damage < 1000 ->
        {world, 0}

      player.armor_type != 0 ->
        saved = if player.armor_type == 1, do: trunc(damage / 3), else: trunc(damage / 2)

        {armor, type, saved} =
          if player.armor <= saved,
            do: {0, 0, player.armor},
            else: {player.armor - saved, player.armor_type, saved}

        {update(world, id, &%{&1 | armor: armor, armor_type: type}), damage - saved}

      true ->
        {world, damage}
    end
  end

  @doc "Player `id` was hurt down to `health` by `source`."
  @spec hurt(World.t(), term(), integer(), number(), map() | nil) :: World.t()
  def hurt(world, id, health, damage, source) do
    update(world, id, fn player ->
      %{
        player
        | health: max(health, 0),
          attacker: source && source.id,
          damage_count: min(player.damage_count + trunc(damage), 100)
      }
    end)
  end

  @doc "Player `id` dies."
  @spec die(World.t(), term(), map() | nil) :: World.t()
  def die(world, id, _source) do
    player = get(world, id)

    world
    |> World.update_mobj(player.mobj, &Mobj.flag(&1, :solid, false))
    |> update(id, &%{&1 | status: :dead})
    |> Weapons.drop(id)
  end

  @doc "A player's death cry, worse for a death by a great deal of damage."
  @spec scream(World.t(), term()) :: World.t()
  def scream(world, mobj_id) do
    mobj = World.mobj(world, mobj_id)
    World.sound(world, if(mobj.health < -50, do: "DSPDIEHI", else: "DSPLDETH"), mobj)
  end

  defp death_think(world, id) do
    world = Weapons.tick(world, id)
    player = get(world, id)
    mobj = World.mobj(world, player.mobj)
    height = max(player.view_height - 1, 6.0)

    world =
      update(world, id, &%{&1 | view_height: height, delta_view: 0.0, view_z: mobj.z + height})

    world = face_killer(world, id)

    if pressed?(player, :use),
      do: update(world, id, &%{&1 | status: :reborn}),
      else: world
  end

  defp face_killer(world, id) do
    player = get(world, id)
    mobj = World.mobj(world, player.mobj)

    case player.attacker && player.attacker != player.mobj && World.mobj(world, player.attacker) do
      %{} = attacker ->
        wanted = Mobj.angle_to(mobj, attacker)
        delta = :math.atan2(:math.sin(wanted - mobj.angle), :math.cos(wanted - mobj.angle))
        step = 5 * :math.pi() / 180

        if abs(delta) < step,
          do: World.put_mobj(world, %{mobj | angle: wanted}),
          else:
            World.put_mobj(world, %{
              mobj
              | angle: mobj.angle + if(delta > 0, do: step, else: -step)
            })

      _none ->
        update(world, id, &%{&1 | damage_count: max(&1.damage_count - 1, 0)})
    end
  end

  defp count_down(world, id) do
    update(world, id, fn player ->
      powers =
        player.powers
        |> Enum.map(fn
          {:strength, tics} -> {:strength, tics + 1}
          {:allmap, value} -> {:allmap, value}
          {power, tics} -> {power, tics - 1}
        end)
        |> Enum.reject(fn {power, tics} -> power not in [:strength, :allmap] and tics <= 0 end)
        |> Map.new()

      %{
        player
        | powers: powers,
          damage_count: max(player.damage_count - 1, 0),
          bonus_count: max(player.bonus_count - 1, 0),
          message_tics: max(player.message_tics - 1, 0)
      }
    end)
  end

  @doc "Show `text` to player `id` for a few seconds."
  @spec message(World.t(), term(), String.t()) :: World.t()
  def message(world, id, text), do: update(world, id, &%{&1 | message: text, message_tics: 140})

  @doc "Whether player thing `mobj_id` sees `target`."
  @spec sees?(World.t(), term(), map()) :: boolean()
  def sees?(world, mobj_id, target), do: Combat.sees?(world, World.mobj(world, mobj_id), target)
end
