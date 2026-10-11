defmodule ElixirDoom.World do
  @moduledoc """
  One level being played: the sectors and sides as they are now, every thing in it, the
  players, the sector machinery at work, and the random draw everything shares.

  A world is a plain value changed by pure functions; `ElixirDoom.Game` drives it a tic
  at a time. Its geometry, `map`, never changes; `sectors` and `sides` do, as floors move
  and switches flip. Things are `mobjs`, keyed by id; `players` key a player's state by
  their id in the game, each holding the id of the thing they move as.
  """

  alias Cauldron2D.Sectors.{Blockmap, Noise}
  alias ElixirDoom.Tables

  @enforce_keys [:level, :map, :blockmap, :sectors, :sides]
  defstruct [
    :level,
    :map,
    :blockmap,
    :noise,
    :sectors,
    :sides,
    :sky,
    skill: 3,
    tic: 0,
    rnd: 0,
    mobjs: %{},
    next_id: 1,
    players: %{},
    thinkers: nil,
    busy: %{},
    used: MapSet.new(),
    targets: %{},
    events: [],
    totals: %{kills: 0, items: 0, secrets: 0},
    exit: nil,
    starts: %{},
    tuning: nil
  ]

  @type t :: %__MODULE__{}

  @scale 40.0

  @doc "A world for `level`, its map's blockmap and sound index built."
  @spec new(ElixirDoom.Level.t(), keyword()) :: t()
  def new(level, opts \\ []) do
    map = level.map

    %__MODULE__{
      level: level.name,
      map: map,
      blockmap: Blockmap.build(map),
      noise: Noise.index(map),
      sectors: map.sectors,
      sides: map.sides,
      sky: level.sky,
      skill: Keyword.get(opts, :skill, 3),
      thinkers: Cauldron2D.Thinkers.new(),
      tuning: Keyword.get(opts, :tuning, ElixirDoom.Tuning.new())
    }
  end

  @doc "The geometry and live sectors in the shape `Cauldron2D.Sectors.Move` takes."
  @spec physics(t()) :: map()
  def physics(%__MODULE__{} = world),
    do: %{map: world.map, blockmap: world.blockmap, sectors: world.sectors}

  @doc "The next draw from the random table, `0..255`."
  @spec random(t()) :: {0..255, t()}
  def random(%__MODULE__{rnd: rnd} = world) do
    next = Bitwise.band(rnd + 1, 255)
    {Tables.random(next), %{world | rnd: next}}
  end

  @doc "The difference of two random draws, `-255..255`, as Doom spreads shots and turns."
  @spec random_spread(t()) :: {integer(), t()}
  def random_spread(world) do
    {a, world} = random(world)
    {b, world} = random(world)
    {a - b, world}
  end

  @doc "Thing `id`, or `nil` once it is gone."
  @spec mobj(t(), term()) :: map() | nil
  def mobj(%__MODULE__{mobjs: mobjs}, id), do: Map.get(mobjs, id)

  @doc "Replace a thing, keeping the blockmap in step with where it is."
  @spec put_mobj(t(), map()) :: t()
  def put_mobj(%__MODULE__{} = world, mobj) do
    world = %{world | mobjs: Map.put(world.mobjs, mobj.id, mobj)}
    file(world, mobj)
  end

  @doc "Remove thing `id` from the world."
  @spec remove_mobj(t(), term()) :: t()
  def remove_mobj(%__MODULE__{} = world, id) do
    %{
      world
      | mobjs: Map.delete(world.mobjs, id),
        blockmap: Blockmap.remove_body(world.blockmap, id)
    }
  end

  @doc "Apply `fun` to thing `id` if it is still there."
  @spec update_mobj(t(), term(), (map() -> map())) :: t()
  def update_mobj(world, id, fun) do
    case mobj(world, id) do
      nil -> world
      mobj -> put_mobj(world, fun.(mobj))
    end
  end

  defp file(world, %{flags: flags} = mobj) do
    if MapSet.member?(flags, :noblockmap) or mobj.state == nil,
      do: %{world | blockmap: Blockmap.remove_body(world.blockmap, mobj.id)},
      else: %{
        world
        | blockmap: Blockmap.put_body(world.blockmap, {mobj.id, {mobj.x, mobj.y}, mobj.radius})
      }
  end

  @doc "A sound heard at a thing's position, or everywhere when `at` is `nil`."
  @spec sound(t(), String.t() | nil, map() | {number(), number()} | nil) :: t()
  def sound(world, nil, _at), do: world
  def sound(world, name, nil), do: %{world | events: [{:sound, name} | world.events]}
  def sound(world, name, %{x: x, y: y}), do: sound(world, name, {x, y})

  def sound(world, name, {x, y}),
    do: %{world | events: [{{:sound, name}, {x / @scale, y / @scale}} | world.events]}

  @doc "How many world units one unit of audio distance is."
  @spec audio_scale() :: float()
  def audio_scale, do: @scale

  @doc "Sector `index` as it is now."
  @spec sector(t(), non_neg_integer()) :: map()
  def sector(%__MODULE__{sectors: sectors}, index), do: elem(sectors, index)

  @doc "Replace sector `index` with `fun.(sector)`."
  @spec update_sector(t(), non_neg_integer(), (map() -> map())) :: t()
  def update_sector(%__MODULE__{} = world, index, fun),
    do: %{world | sectors: put_elem(world.sectors, index, fun.(elem(world.sectors, index)))}

  @doc "The setting `key` of the world's tuning."
  @spec tuning(t(), atom()) :: term()
  def tuning(%__MODULE__{tuning: tuning}, key), do: Cauldron2D.Tuning.get(tuning, key)

  @doc "Add `amount` to total `key`."
  @spec count(t(), atom(), integer()) :: t()
  def count(world, key, amount \\ 1),
    do: %{world | totals: Map.update!(world.totals, key, &(&1 + amount))}
end
