defmodule ElixirDoom.Items do
  @moduledoc """
  Picking things up: what each pickup gives, the message it shows, the sound it makes,
  and whether it is taken at all — a full medikit is left lying when health is full.

      ElixirDoom.Items.touch(world, item_id, player_mobj_id)
  """

  alias ElixirDoom.{Mobj, Player, Tables, Weapons, World}

  @empty_switch %{
    clip: {[:fist], [:chaingun, :pistol]},
    shell: {[:fist, :pistol], [:shotgun]},
    cell: {[:fist, :pistol], [:plasma]},
    misl: {[:fist], [:missile]}
  }

  @doc "Player thing `toucher_id` touches item `item_id`."
  @spec touch(World.t(), term(), term()) :: World.t()
  def touch(world, item_id, toucher_id) do
    item = World.mobj(world, item_id)
    toucher = World.mobj(world, toucher_id)

    cond do
      toucher.player == nil or toucher.health <= 0 -> world
      item.z - toucher.z > toucher.height or item.z - toucher.z < -8 -> world
      true -> take(world, item, toucher)
    end
  end

  defp take(world, item, toucher) do
    {sprite, _frame, _bright} = item.picture
    id = toucher.player

    case give(world, id, sprite, Mobj.flag?(item, :dropped)) do
      :leave ->
        world

      {world, message, sound} ->
        world = if Mobj.flag?(item, :countitem), do: World.count(world, :items), else: world

        world
        |> World.remove_mobj(item.id)
        |> Player.update(id, &%{&1 | bonus_count: &1.bonus_count + 6})
        |> Player.message(id, message)
        |> World.sound(sound, nil)
    end
  end

  defp give(world, id, "ARM1", _dropped), do: armor(world, id, 1, "Picked up the armor.")
  defp give(world, id, "ARM2", _dropped), do: armor(world, id, 2, "Picked up the MegaArmor!")

  defp give(world, id, "BON1", _dropped) do
    {heal(world, id, 1, 200), "Picked up a health bonus.", "DSITEMUP"}
  end

  defp give(world, id, "BON2", _dropped) do
    world =
      Player.update(world, id, fn player ->
        %{player | armor: min(player.armor + 1, 200), armor_type: max(player.armor_type, 1)}
      end)

    {world, "Picked up an armor bonus.", "DSITEMUP"}
  end

  defp give(world, id, "SOUL", _dropped),
    do: {heal(world, id, 100, 200), "Supercharge!", "DSGETPOW"}

  defp give(world, id, "MEGA", _dropped),
    do: {world |> set_health(id, 200) |> set_armor(id, 200, 2), "MegaSphere!", "DSGETPOW"}

  defp give(world, id, "BKEY", _dropped),
    do: card(world, id, :blue_card, "Picked up a blue keycard.")

  defp give(world, id, "YKEY", _dropped),
    do: card(world, id, :yellow_card, "Picked up a yellow keycard.")

  defp give(world, id, "RKEY", _dropped),
    do: card(world, id, :red_card, "Picked up a red keycard.")

  defp give(world, id, "BSKU", _dropped),
    do: card(world, id, :blue_skull, "Picked up a blue skull key.")

  defp give(world, id, "YSKU", _dropped),
    do: card(world, id, :yellow_skull, "Picked up a yellow skull key.")

  defp give(world, id, "RSKU", _dropped),
    do: card(world, id, :red_skull, "Picked up a red skull key.")

  defp give(world, id, "STIM", _dropped), do: body(world, id, 10, "Picked up a stimpack.")

  defp give(world, id, "MEDI", _dropped) do
    low? = Player.get(world, id).health < 25

    body(
      world,
      id,
      25,
      if(low?, do: "Picked up a medikit that you REALLY need!", else: "Picked up a medikit.")
    )
  end

  defp give(world, id, "PINV", _dropped),
    do: power(world, id, :invulnerability, 30 * 35, "Invulnerability!")

  defp give(world, id, "PSTR", _dropped) do
    world =
      world
      |> heal_to(id, 100)
      |> Player.update(id, &%{&1 | pending: if(&1.ready != :fist, do: :fist, else: &1.pending)})

    power(world, id, :strength, 1, "Berserk!")
  end

  defp give(world, id, "PINS", _dropped) do
    player = Player.get(world, id)
    world = World.update_mobj(world, player.mobj, &Mobj.flag(&1, :shadow, true))
    power(world, id, :invisibility, 60 * 35, "Partial Invisibility")
  end

  defp give(world, id, "SUIT", _dropped),
    do: power(world, id, :ironfeet, 60 * 35, "Radiation Shielding Suit")

  defp give(world, id, "PMAP", _dropped), do: power(world, id, :allmap, 1, "Computer Area Map")

  defp give(world, id, "PVIS", _dropped),
    do: power(world, id, :infrared, 120 * 35, "Light Amplification Visor")

  defp give(world, id, "CLIP", dropped),
    do: ammo(world, id, :clip, if(dropped, do: 0, else: 1), "Picked up a clip.")

  defp give(world, id, "AMMO", _dropped),
    do: ammo(world, id, :clip, 5, "Picked up a box of bullets.")

  defp give(world, id, "ROCK", _dropped), do: ammo(world, id, :misl, 1, "Picked up a rocket.")

  defp give(world, id, "BROK", _dropped),
    do: ammo(world, id, :misl, 5, "Picked up a box of rockets.")

  defp give(world, id, "CELL", _dropped),
    do: ammo(world, id, :cell, 1, "Picked up an energy cell.")

  defp give(world, id, "CELP", _dropped),
    do: ammo(world, id, :cell, 5, "Picked up an energy cell pack.")

  defp give(world, id, "SHEL", _dropped),
    do: ammo(world, id, :shell, 1, "Picked up 4 shotgun shells.")

  defp give(world, id, "SBOX", _dropped),
    do: ammo(world, id, :shell, 5, "Picked up a box of shotgun shells.")

  defp give(world, id, "BPAK", _dropped) do
    player = Player.get(world, id)

    world =
      if player.backpack,
        do: world,
        else:
          Player.update(
            world,
            id,
            &%{&1 | backpack: true, max_ammo: Map.new(&1.max_ammo, fn {k, v} -> {k, v * 2} end)}
          )

    world =
      Enum.reduce([:clip, :shell, :cell, :misl], world, fn kind, acc ->
        elem(add_ammo(acc, id, kind, 1), 0)
      end)

    {world, "Picked up a backpack full of ammo!", "DSITEMUP"}
  end

  defp give(world, id, "BFUG", dropped),
    do: weapon(world, id, :bfg, dropped, "You got the BFG9000!  Oh, yes.")

  defp give(world, id, "MGUN", dropped),
    do: weapon(world, id, :chaingun, dropped, "You got the chaingun!")

  defp give(world, id, "CSAW", dropped),
    do: weapon(world, id, :chainsaw, dropped, "A chainsaw!  Find some meat!")

  defp give(world, id, "LAUN", dropped),
    do: weapon(world, id, :missile, dropped, "You got the rocket launcher!")

  defp give(world, id, "PLAS", dropped),
    do: weapon(world, id, :plasma, dropped, "You got the plasma gun!")

  defp give(world, id, "SHOT", dropped),
    do: weapon(world, id, :shotgun, dropped, "You got the shotgun!")

  defp give(_world, _id, _sprite, _dropped), do: :leave

  defp armor(world, id, type, message) do
    points = type * 100

    if Player.get(world, id).armor >= points,
      do: :leave,
      else: {set_armor(world, id, points, type), message, "DSITEMUP"}
  end

  defp set_armor(world, id, points, type),
    do: Player.update(world, id, &%{&1 | armor: points, armor_type: type})

  defp heal(world, id, amount, cap) do
    player = Player.get(world, id)
    set_health(world, id, min(player.health + amount, cap))
  end

  defp heal_to(world, id, floor) do
    player = Player.get(world, id)
    if player.health < floor, do: set_health(world, id, floor), else: world
  end

  defp set_health(world, id, health) do
    player = Player.get(world, id)

    world
    |> Player.update(id, &%{&1 | health: health})
    |> World.update_mobj(player.mobj, &%{&1 | health: health})
  end

  defp body(world, id, amount, message) do
    if Player.get(world, id).health >= 100,
      do: :leave,
      else: {heal(world, id, amount, 100), message, "DSITEMUP"}
  end

  defp card(world, id, key, message) do
    if MapSet.member?(Player.get(world, id).cards, key),
      do: :leave,
      else:
        {Player.update(world, id, &%{&1 | cards: MapSet.put(&1.cards, key)}), message, "DSITEMUP"}
  end

  defp power(world, id, power, tics, message) do
    {Player.update(world, id, &%{&1 | powers: Map.put(&1.powers, power, tics)}), message,
     "DSGETPOW"}
  end

  defp ammo(world, id, kind, clips, message) do
    case add_ammo(world, id, kind, clips) do
      {_world, false} -> :leave
      {world, true} -> {world, message, "DSITEMUP"}
    end
  end

  @doc "Give player `id` `clips` clips of ammunition `kind` (`0` for half a clip): `{world, taken?}`."
  @spec add_ammo(World.t(), term(), atom(), non_neg_integer()) :: {World.t(), boolean()}
  def add_ammo(world, id, kind, clips) do
    player = Player.get(world, id)
    have = Map.get(player.ammo, kind, 0)
    max = Map.fetch!(player.max_ammo, kind)

    if have >= max do
      {world, false}
    else
      amount =
        if clips == 0, do: div(Tables.clip_ammo(kind), 2), else: clips * Tables.clip_ammo(kind)

      amount = if world.skill in [1, 5], do: amount * 2, else: amount

      world =
        Player.update(world, id, &%{&1 | ammo: Map.put(&1.ammo, kind, min(have + amount, max))})

      {switch_on_empty(world, id, kind, have), true}
    end
  end

  defp switch_on_empty(world, id, kind, 0) do
    player = Player.get(world, id)
    {from, choices} = Map.fetch!(@empty_switch, kind)

    pending =
      if player.ready in from,
        do: Enum.find(choices, &MapSet.member?(player.weapons, &1))

    if pending, do: Player.update(world, id, &%{&1 | pending: pending}), else: world
  end

  defp switch_on_empty(world, _id, _kind, _have), do: world

  defp weapon(world, id, weapon, dropped, message) do
    player = Player.get(world, id)
    kind = Tables.weapon(weapon).ammo

    {world, got_ammo?} =
      if kind, do: add_ammo(world, id, kind, if(dropped, do: 1, else: 2)), else: {world, false}

    new? = not MapSet.member?(player.weapons, weapon)

    world =
      if new?,
        do:
          Player.update(
            world,
            id,
            &%{&1 | weapons: MapSet.put(&1.weapons, weapon), pending: weapon}
          ),
        else: world

    if new? or got_ammo?,
      do: {world, message, "DSWPNUP"},
      else: :leave
  end

  @doc "Whether `player` may fire `weapon` now."
  @spec usable?(map(), atom()) :: boolean()
  def usable?(player, weapon),
    do: MapSet.member?(player.weapons, weapon) and Weapons.has_ammo?(player, weapon)
end
