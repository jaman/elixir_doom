defmodule ElixirDoom.Tuning do
  @moduledoc """
  The numbers that decide how Doom moves and fights, as a `Cauldron2D.Tuning`. Defaults
  are Doom's own; `config :elixir_doom, <setting>, value` moves a default, and
  `ElixirDoom.Game.init/1`'s `:tuning` option beats both.

  ## Settings

    * `:friction` — the share of its speed a thing on the ground keeps each tic
    * `:gravity` — units a tic a falling thing gains each tic
    * `:max_move` — the fastest a thing moves, units a tic
    * `:step` — the highest step a walker climbs, units
    * `:view_height` — the player's eye above their feet, units
    * `:walk` and `:run` — forward thrust a tic walking and running, units a tic
    * `:strafe_walk` and `:strafe_run` — sideways thrust a tic
    * `:turn_slow`, `:turn_walk` and `:turn_run` — radians a tic turned: for the first
      `:slow_turn_tics` of a turn, then walking or running
    * `:max_bob` — how far the view bobs while moving, units
    * `:use_range` — how far a player reaches to use a switch or door, units
    * `:melee_range` — how far a punch or bite reaches, units
    * `:missile_range` — how far an instant-hit weapon reaches, units
    * `:weapon_speed` — how fast a weapon is raised and lowered, units a tic
    * `:always_run` — run without holding the run key
  """

  alias Cauldron2D.Tuning

  @spec_list [
    friction: [default: 0.90625, limits: {0.5, 0.99}, doc: "speed kept a tic on the ground"],
    gravity: [default: 1.0, limits: {0.1, 4.0}, doc: "units a tic gained falling each tic"],
    max_move: [default: 30.0, limits: {8.0, 60.0}, doc: "fastest speed, units a tic"],
    step: [default: 24.0, limits: {0.0, 64.0}, doc: "highest step climbed, units"],
    view_height: [default: 41.0, limits: {16.0, 52.0}, doc: "eye above the feet, units"],
    walk: [default: 25 / 32, limits: {0.1, 4.0}, doc: "forward thrust walking"],
    run: [default: 50 / 32, limits: {0.1, 6.0}, doc: "forward thrust running"],
    strafe_walk: [default: 24 / 32, limits: {0.1, 4.0}, doc: "side thrust walking"],
    strafe_run: [default: 40 / 32, limits: {0.1, 6.0}, doc: "side thrust running"],
    turn_slow: [
      default: 320 / 65_536 * 2 * :math.pi(),
      limits: {0.005, 0.2},
      doc: "radians a tic, first tics of a turn"
    ],
    turn_walk: [
      default: 640 / 65_536 * 2 * :math.pi(),
      limits: {0.01, 0.3},
      doc: "radians a tic walking"
    ],
    turn_run: [
      default: 1280 / 65_536 * 2 * :math.pi(),
      limits: {0.01, 0.4},
      doc: "radians a tic running"
    ],
    slow_turn_tics: [default: 6, limits: {0, 35}, doc: "tics a turn starts slowly"],
    max_bob: [default: 16.0, limits: {0.0, 32.0}, doc: "view bob, units"],
    use_range: [default: 64.0, limits: {16.0, 256.0}, doc: "reach for switches and doors"],
    melee_range: [default: 64.0, limits: {16.0, 256.0}, doc: "punch and bite reach"],
    missile_range: [default: 2048.0, limits: {256.0, 8192.0}, doc: "instant-hit reach"],
    weapon_speed: [default: 6.0, limits: {1.0, 24.0}, doc: "weapon raise and lower, units a tic"],
    always_run: [default: false, doc: "run without holding the run key"]
  ]

  @doc "The settings with each default taken from config where config sets one."
  @spec spec() :: Tuning.spec()
  def spec do
    Enum.map(@spec_list, fn {key, options} ->
      {key,
       Keyword.put(options, :default, Application.get_env(:elixir_doom, key, options[:default]))}
    end)
  end

  @doc "A tuning with `overrides` over the defaults."
  @spec new(keyword() | map()) :: Tuning.t()
  def new(overrides \\ []), do: Tuning.new(spec(), overrides)
end
