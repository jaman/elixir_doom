defmodule ElixirDoom.Game do
  @moduledoc """
  Doom as a `Cauldron2D.Game`: an episode played level by level at 35 tics a second.

      Cauldron2D.World.start_link(game: ElixirDoom.Game, game_opts: [level: "E1M1", skill: 3], hz: 35)

  Options: `:level` to start on (default the WAD's first), `:skill` `1..5` (default `3`),
  `:tuning` overrides for `ElixirDoom.Tuning`. A WAD must have been loaded with
  `ElixirDoom.Assets.load/1` first.

  A level ends at an exit; the game shows the tallies until a player presses use or fire,
  then carries every player's health, armour, weapons and ammunition into the next. A
  player who dies presses use to start the level again from scratch. After the episode's
  last level the game is over.
  """

  @behaviour Cauldron2D.Game

  alias Cauldron2D.Sectors.Map, as: SectorMap
  alias ElixirDoom.{Assets, Info, Mobj, Player, Specials, World}

  @impl true
  def init(opts) do
    assets = Assets.get()
    level = Keyword.get(opts, :level) || hd(assets.levels)
    skill = Keyword.get(opts, :skill, 3)
    tuning = ElixirDoom.Tuning.new(Keyword.get(opts, :tuning, []))

    %{
      phase: :level,
      level: level,
      skill: skill,
      tuning: tuning,
      world: start_level(level, skill, tuning),
      carried: %{},
      tally: nil,
      wait: 0,
      events: [],
      request: 0
    }
  end

  defp start_level(name, skill, tuning) do
    {:ok, level} = Assets.level(name)
    world = World.new(level, skill: skill, tuning: tuning)

    level.things
    |> Enum.reduce(world, &place_thing/2)
    |> Specials.spawn_sector_specials()
  end

  defp place_thing(thing, world) do
    cond do
      thing.type in 1..4 -> %{world | starts: Map.put(world.starts, thing.type, thing)}
      thing.type == 11 -> world
      Bitwise.band(thing.flags, 16) != 0 -> world
      Bitwise.band(thing.flags, skill_bit(world.skill)) == 0 -> world
      true -> spawn_thing(world, thing)
    end
  end

  defp skill_bit(skill) when skill in [1, 2], do: 1
  defp skill_bit(3), do: 2
  defp skill_bit(_skill), do: 4

  defp spawn_thing(world, thing) do
    case Info.by_doomednum(thing.type) do
      nil ->
        world

      type ->
        info = Info.thing(type)
        z = if :spawnceiling in info.flags, do: :ceiling, else: :floor
        {world, id} = Mobj.spawn(world, type, {thing.x, thing.y, z}, thing.angle)

        world =
          if Bitwise.band(thing.flags, 8) != 0,
            do: World.update_mobj(world, id, &Mobj.flag(&1, :ambush, true)),
            else: world

        world = if :countkill in info.flags, do: count_total(world, :kill_total), else: world
        world = if :countitem in info.flags, do: count_total(world, :item_total), else: world
        mobj = World.mobj(world, id)

        if mobj.tics > 0 do
          {roll, world} = World.random(world)
          World.put_mobj(world, %{mobj | tics: 1 + rem(roll, mobj.tics)})
        else
          world
        end
    end
  end

  defp count_total(world, key), do: %{world | totals: Map.update(world.totals, key, 1, &(&1 + 1))}

  @impl true
  def join(state, id, _props) do
    carried = Map.get(state.carried, id, Player.fresh(id))
    {:ok, %{state | world: enter(state.world, id, carried)}}
  end

  defp enter(world, id, player) do
    number = map_size(world.players) + 1

    start =
      Map.get(world.starts, number) || Map.get(world.starts, 1) || %{x: 0.0, y: 0.0, angle: 0.0}

    {world, mobj_id} = Mobj.spawn(world, :mt_player, {start.x, start.y, :floor}, start.angle)
    world = World.update_mobj(world, mobj_id, &%{&1 | player: id, health: player.health})
    mobj = World.mobj(world, mobj_id)

    player = %{
      player
      | mobj: mobj_id,
        view_z: mobj.z + World.tuning(world, :view_height),
        view_height: World.tuning(world, :view_height),
        status: :alive
    }

    world = %{world | players: Map.put(world.players, id, player)}
    ElixirDoom.Weapons.bring_up(world, id)
  end

  @impl true
  def leave(state, id) do
    world = state.world

    case Player.get(world, id) do
      nil ->
        state

      player ->
        %{
          state
          | world: %{
              World.remove_mobj(world, player.mobj)
              | players: Map.delete(world.players, id)
            }
        }
    end
  end

  @impl true
  def handle_input(state, id, %{request: {n, {:new_game, episode, skill}}} = input)
      when n > state.request do
    fresh = init(level: "E#{episode}M1", skill: skill)
    {:ok, fresh} = join(%{fresh | request: n}, id, %{})
    handle_input(fresh, id, Map.delete(input, :request))
  end

  def handle_input(state, id, %{held: held} = input) do
    strength = Map.get(input, :strength, %{})
    %{state | world: Player.update(state.world, id, &%{&1 | held: held, strength: strength})}
  end

  @impl true
  def step(%{phase: :level} = state, _dt) do
    world = tic(state.world)

    cond do
      world.exit != nil ->
        finish_level(%{state | world: world})

      Enum.any?(Map.values(world.players), &(&1.status == :reborn)) ->
        restart(%{state | world: world})

      true ->
        %{state | world: world}
    end
  end

  def step(%{phase: phase} = state, _dt) when phase in [:intermission, :finale] do
    world = state.world

    pressed? =
      Enum.any?(
        Map.values(world.players),
        &(Player.pressed?(&1, :use) or Player.pressed?(&1, :fire))
      )

    players =
      Map.new(world.players, fn {id, player} -> {id, %{player | previous: player.held}} end)

    state = %{state | world: %{world | players: players}, wait: state.wait + 1}

    if pressed? and state.wait > 35, do: advance(state), else: state
  end

  def step(state, _dt), do: state

  defp tic(world) do
    world = Enum.reduce(Map.keys(world.players), world, &Player.think(&2, &1))
    world = Specials.think(world)

    world =
      world.mobjs
      |> Map.keys()
      |> Enum.sort()
      |> Enum.reduce(world, &Mobj.tick(&2, &1))

    %{world | tic: world.tic + 1}
  end

  defp finish_level(state) do
    world = state.world

    tally = %{
      level: state.level,
      kills: world.totals.kills,
      kill_total: Map.get(world.totals, :kill_total, 0),
      items: world.totals.items,
      item_total: Map.get(world.totals, :item_total, 0),
      secrets: world.totals.secrets,
      secret_total: Map.get(world.totals, :secret_total, 0),
      seconds: div(world.tic, 35),
      next: next_level(state.level, world.exit)
    }

    carried = Map.new(world.players, fn {id, player} -> {id, carry(world, player)} end)
    %{state | phase: :intermission, tally: tally, carried: carried, wait: 0}
  end

  defp carry(world, player) do
    mobj = World.mobj(world, player.mobj)

    %{
      player
      | health: (mobj && mobj.health) || player.health,
        powers: %{},
        cards: MapSet.new(),
        extra_light: 0,
        damage_count: 0,
        bonus_count: 0,
        message: nil,
        pending: nil,
        weapon: %{state: nil, tics: -1, sx: 1.0, sy: 128.0},
        flash: %{state: nil, tics: -1, sx: 1.0, sy: 128.0},
        attacker: nil
    }
  end

  defp advance(%{phase: :intermission, tally: %{next: nil}} = state),
    do: %{state | phase: :finale, wait: 0}

  defp advance(%{phase: :intermission, tally: %{next: next}} = state) do
    world = start_level(next, state.skill, state.tuning)
    world = Enum.reduce(state.carried, world, fn {id, player}, acc -> enter(acc, id, player) end)
    %{state | phase: :level, level: next, world: world, tally: nil, wait: 0}
  end

  defp advance(%{phase: :finale} = state), do: %{state | phase: :over}

  defp restart(state) do
    world = start_level(state.level, state.skill, state.tuning)

    world =
      Enum.reduce(state.world.players, world, fn {id, _player}, acc ->
        enter(acc, id, Player.fresh(id))
      end)

    %{state | world: world}
  end

  @doc "The level that follows `level`, by a normal or a secret exit, or `nil` at an episode's end."
  @spec next_level(String.t(), :normal | :secret) :: String.t() | nil
  def next_level(<<"E", episode, "M", map>>, exit) do
    {episode, map} = {episode - ?0, map - ?0}
    back = %{1 => 4, 2 => 6, 3 => 7, 4 => 3}

    candidate =
      cond do
        exit == :secret -> 9
        map == 9 -> back[episode]
        map == 8 -> nil
        true -> map + 1
      end

    if candidate, do: available("E#{episode}M#{candidate}")
  end

  def next_level("MAP" <> number, exit) do
    map = String.to_integer(number)

    candidate =
      cond do
        exit == :secret and map == 15 -> 31
        exit == :secret and map == 31 -> 32
        map in [31, 32] -> 16
        map == 30 -> nil
        true -> map + 1
      end

    if candidate, do: available("MAP" <> String.pad_leading(Integer.to_string(candidate), 2, "0"))
  end

  defp available(name), do: if(name in Assets.get().levels, do: name)

  @impl true
  def view(%{phase: :level} = state, id) do
    world = state.world

    case Player.get(world, id) do
      nil -> %{phase: :level, me: nil, level: state.level}
      player -> level_view(world, state, player)
    end
  end

  def view(state, id) do
    %{
      phase: state.phase,
      level: state.level,
      tally: state.tally,
      me: Player.get(state.world, id) && %{}
    }
  end

  defp level_view(world, state, player) do
    me = World.mobj(world, player.mobj)
    assets = Assets.get()
    frame = Assets.animation_frame(assets, world.tic)

    %{
      phase: :level,
      level: state.level,
      tic: world.tic,
      me: me,
      player: Map.drop(player, [:held, :previous]),
      eye: %{x: me.x, y: me.y, z: player.view_z, angle: me.angle},
      sectors: animate_sectors(world.sectors, frame),
      sides: animate_sides(world.sides, frame),
      things: things(world, me),
      sky: world.sky,
      totals: world.totals
    }
  end

  defp animate_sectors(sectors, frame) when map_size(frame) == 0, do: sectors

  defp animate_sectors(sectors, frame) do
    sectors
    |> Tuple.to_list()
    |> Enum.map(fn sector ->
      %{
        sector
        | floor_picture: Map.get(frame, sector.floor_picture, sector.floor_picture),
          ceiling_picture: Map.get(frame, sector.ceiling_picture, sector.ceiling_picture)
      }
    end)
    |> List.to_tuple()
  end

  defp animate_sides(sides, frame) when map_size(frame) == 0, do: sides

  defp animate_sides(sides, frame) do
    sides
    |> Tuple.to_list()
    |> Enum.map(fn side ->
      %{
        side
        | upper: swap(frame, side.upper),
          middle: swap(frame, side.middle),
          lower: swap(frame, side.lower)
      }
    end)
    |> List.to_tuple()
  end

  defp swap(_frame, nil), do: nil
  defp swap(frame, picture), do: Map.get(frame, picture, picture)

  defp things(world, me) do
    graphics = Assets.get().graphics

    world.mobjs
    |> Map.values()
    |> Enum.reject(&(&1.id == me.id or &1.state == nil or Mobj.flag?(&1, :nosector)))
    |> Enum.flat_map(fn mobj ->
      {sprite, frame, bright} = mobj.picture
      rotation = rotation(me, mobj)

      case ElixirDoom.Graphics.sprite(graphics, sprite, frame, rotation) do
        nil ->
          []

        {picture, flip, lump} ->
          info = ElixirDoom.Graphics.patch_info(graphics, lump)
          offset = {info.left, info.top}

          [
            %{
              id: mobj.id,
              x: mobj.x,
              y: mobj.y,
              z: mobj.z,
              sector: mobj.sector,
              picture: picture,
              offset: offset,
              flip: flip,
              bright: bright,
              shimmer: Mobj.flag?(mobj, :shadow)
            }
          ]
      end
    end)
  end

  defp rotation(viewer, mobj) do
    seen_from = :math.atan2(mobj.y - viewer.y, mobj.x - viewer.x)
    turn = seen_from - mobj.angle + :math.pi() + :math.pi() / 8
    eighth = :math.pi() / 4
    turn = turn - 2 * :math.pi() * Float.floor(turn / (2 * :math.pi()))
    rem(trunc(turn / eighth), 8)
  end

  @impl true
  def drain_events(%{world: world} = state) do
    {Enum.reverse(world.events), %{state | world: %{world | events: []}}}
  end

  @doc "The sector `point` is in, in the current level."
  @spec sector_at(map(), {number(), number()}) :: non_neg_integer()
  def sector_at(state, point), do: SectorMap.sector_at(state.world.map, point)
end
