defmodule ElixirDoom.Specials.Doors do
  @moduledoc """
  Starting doors: the ones a player opens by hand — the sector behind the line used,
  some locked to a key — and the ones a line opens or shuts by tag.

  Door kinds are `:normal` (opens, waits, closes), `:open`, `:close`,
  `:close_30_then_open`, `:raise_in_5_mins`, and the fast `:blaze_raise`, `:blaze_open`
  and `:blaze_close`.
  """

  alias Cauldron2D.Sectors.Map, as: SectorMap
  alias ElixirDoom.{Player, World}
  alias ElixirDoom.Specials.{Machines, Sectors, Switches}

  @speed 2.0
  @wait 150
  @manual %{
    1 => :normal,
    26 => :normal,
    27 => :normal,
    28 => :normal,
    31 => :open,
    32 => :open,
    33 => :open,
    34 => :open,
    117 => :blaze_raise,
    118 => :blaze_open
  }
  @keys %{
    26 => {[:blue_card, :blue_skull], "You need a blue key to open this door"},
    32 => {[:blue_card, :blue_skull], "You need a blue key to open this door"},
    27 => {[:yellow_card, :yellow_skull], "You need a yellow key to open this door"},
    34 => {[:yellow_card, :yellow_skull], "You need a yellow key to open this door"},
    28 => {[:red_card, :red_skull], "You need a red key to open this door"},
    33 => {[:red_card, :red_skull], "You need a red key to open this door"}
  }

  @doc "Whether line special `special` is a door opened by hand."
  @spec manual?(integer()) :: boolean()
  def manual?(special), do: Map.has_key?(@manual, special)

  @doc "Thing `id` opens by hand the door behind line `index`, which has special `special`."
  @spec by_hand(World.t(), term(), non_neg_integer(), integer()) :: World.t()
  def by_hand(world, id, index, special) do
    mobj = World.mobj(world, id)

    case lock(world, mobj, special) do
      :open ->
        open_behind(world, id, index, special)

      {:locked, nil} ->
        world

      {:locked, message} ->
        world |> Player.message(mobj.player, message) |> World.sound("DSOOF", mobj)
    end
  end

  defp lock(world, mobj, special) do
    case Map.get(@keys, special) do
      nil -> :open
      {_keys, _message} when mobj.player == nil -> {:locked, nil}
      {keys, message} -> if holds?(world, mobj, keys), do: :open, else: {:locked, message}
    end
  end

  defp holds?(world, mobj, keys) do
    cards = Player.get(world, mobj.player).cards
    Enum.any?(keys, &MapSet.member?(cards, &1))
  end

  defp open_behind(world, id, index, special) do
    case SectorMap.side_sector(world.map, index, 1) do
      nil -> world
      sector -> toggle_or_start(world, id, index, special, sector)
    end
  end

  defp toggle_or_start(world, id, index, special, sector) do
    case Machines.mover(world, sector) do
      nil ->
        start_by_hand(world, index, special, sector)

      {thinker_id, %{kind: :door} = door} when special in [1, 26, 27, 28, 117] ->
        toggle(world, id, thinker_id, door)

      _other ->
        world
    end
  end

  defp toggle(world, id, thinker_id, door) do
    direction =
      cond do
        door.direction == -1 -> 1
        World.mobj(world, id).player == nil -> door.direction
        true -> -1
      end

    Machines.update(world, thinker_id, &%{&1 | direction: direction})
  end

  defp start_by_hand(world, index, special, sector) do
    type = Map.fetch!(@manual, special)
    blaze? = type in [:blaze_raise, :blaze_open]

    world
    |> Machines.start_mover(
      sector,
      door(world, sector, type, 1, Sectors.lowest_ceiling(world, sector) - 4)
    )
    |> Sectors.sound(sector, if(blaze?, do: "DSBDOPN", else: "DSDOROPN"))
    |> Switches.mark_used(index, type in [:open, :blaze_open])
  end

  @doc "Start door `type` in every sector tagged `tag` that no mover has taken: `{world, started?}`."
  @spec by_tag(World.t(), integer(), atom()) :: {World.t(), boolean()}
  def by_tag(world, tag, type) do
    world
    |> Sectors.tagged(tag)
    |> Enum.reject(&Machines.busy?(world, &1))
    |> Enum.reduce({world, false}, fn sector, {acc, _started?} ->
      {start(acc, sector, type), true}
    end)
  end

  @doc "A door of `type` waiting in sector `index` from the level's start, `countdown` tics."
  @spec timed(World.t(), non_neg_integer(), :normal | :raise_in_5_mins, pos_integer()) ::
          World.t()
  def timed(world, index, :normal, countdown),
    do:
      Machines.start_mover(world, index, %{
        door(world, index, :normal, 0, World.sector(world, index).ceiling)
        | countdown: countdown
      })

  def timed(world, index, :raise_in_5_mins, countdown),
    do:
      Machines.start_mover(world, index, %{
        door(world, index, :raise_in_5_mins, 2, Sectors.lowest_ceiling(world, index) - 4)
        | countdown: countdown
      })

  defp start(world, sector, type) when type in [:close, :blaze_close] do
    sound = if type == :blaze_close, do: "DSBDCLS", else: "DSDORCLS"

    world
    |> Machines.start_mover(
      sector,
      door(world, sector, type, -1, Sectors.lowest_ceiling(world, sector) - 4)
    )
    |> Sectors.sound(sector, sound)
  end

  defp start(world, sector, :close_30_then_open) do
    world
    |> Machines.start_mover(
      sector,
      door(world, sector, :close_30_then_open, -1, World.sector(world, sector).ceiling)
    )
    |> Sectors.sound(sector, "DSDORCLS")
  end

  defp start(world, sector, type) do
    top = Sectors.lowest_ceiling(world, sector) - 4
    world = Machines.start_mover(world, sector, door(world, sector, type, 1, top))
    sound = if type in [:blaze_raise, :blaze_open], do: "DSBDOPN", else: "DSDOROPN"

    if top != World.sector(world, sector).ceiling,
      do: Sectors.sound(world, sector, sound),
      else: world
  end

  defp door(_world, sector, type, direction, top) do
    blaze? = type in [:blaze_raise, :blaze_open, :blaze_close]

    %{
      kind: :door,
      type: type,
      sector: sector,
      direction: direction,
      speed: if(blaze?, do: @speed * 4, else: @speed),
      top: top,
      wait: @wait,
      countdown: 0
    }
  end
end
