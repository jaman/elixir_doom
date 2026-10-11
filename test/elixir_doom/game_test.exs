defmodule ElixirDoom.GameTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Sectors.Map, as: SectorMap
  alias ElixirDoom.{Assets, Combat, Game, Specials, World}

  @wad System.get_env("DOOM_WAD")

  describe "progression" do
    setup do
      :persistent_term.put({Assets, :assets}, %Assets{
        wad: nil,
        graphics: nil,
        switches: %{},
        animations: [],
        levels: ~w(E1M1 E1M2 E1M3 E1M4 E1M5 E1M6 E1M7 E1M8 E1M9 MAP15 MAP16 MAP31 MAP32)
      })

      on_exit(fn -> :persistent_term.erase({Assets, :assets}) end)
    end

    test "levels follow in order, secret exits lead to the secret level and back, an episode ends" do
      assert Game.next_level("E1M1", :normal) == "E1M2"
      assert Game.next_level("E1M3", :secret) == "E1M9"
      assert Game.next_level("E1M9", :normal) == "E1M4"
      assert Game.next_level("E1M8", :normal) == nil
      assert Game.next_level("MAP15", :secret) == "MAP31"
      assert Game.next_level("MAP31", :secret) == "MAP32"
      assert Game.next_level("MAP32", :normal) == "MAP16"
    end
  end

  describe "playing a WAD" do
    @describetag skip: if(@wad, do: false, else: "set DOOM_WAD to a Doom WAD to play it")

    setup do
      {:ok, _assets} = Assets.load(@wad)
      state = Game.init(level: "E1M1", skill: 3)
      {:ok, state} = Game.join(state, :player, %{})
      {:ok, state: state}
    end

    defp run(state, held, tics) do
      state = Game.handle_input(state, :player, %{held: MapSet.new(held), aim: nil})
      Enum.reduce(1..tics, state, fn _tic, acc -> Game.step(acc, 1 / 35) end)
    end

    test "a used door opens, waits, and closes again by itself", %{state: state} do
      world = state.world
      me = world.players[:player].mobj

      door =
        Enum.find(0..(tuple_size(world.map.lines) - 1), &(elem(world.map.lines, &1).special == 1))

      sector = SectorMap.side_sector(world.map, door, 1)
      shut = World.sector(world, sector).ceiling

      {:used, world} = Specials.use_line(world, me, door, 0)
      opened = run(%{state | world: world}, [], 70)
      assert World.sector(opened.world, sector).ceiling > shut + 50

      closed = run(opened, [], 300)
      assert World.sector(closed.world, sector).ceiling == shut
    end

    test "a dead player who presses use starts the level again with a pistol", %{state: state} do
      me = state.world.players[:player].mobj
      state = %{state | world: Combat.damage(state.world, me, nil, nil, 1000)}
      state = run(state, [], 10)
      assert state.world.players[:player].status == :dead

      state = run(state, [:use], 1) |> run([], 1)
      player = state.world.players[:player]

      assert player.status == :alive
      assert player.health == 100
      assert player.ammo.clip == 50
      assert state.world.tic < 5
    end
  end
end
