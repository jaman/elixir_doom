defmodule ElixirDoom.Specials.Lights do
  @moduledoc """
  Sector lights that change by themselves — flickering, strobing, glowing — and lines
  that set a tagged sector's light.

  `step/3` is a `Cauldron2D.Thinkers` step for a light of kind `:flash`, `:strobe` or
  `:glow`.
  """

  alias ElixirDoom.Specials.{Machines, Sectors}
  alias ElixirDoom.World

  @glow_speed 8
  @strobe_bright 5

  @doc "Start a random flicker in sector `index` between its light and its dimmest neighbour's."
  @spec flicker(World.t(), non_neg_integer()) :: World.t()
  def flicker(world, index) do
    sector = World.sector(world, index)
    {roll, world} = World.random(world)

    Machines.start(world, %{
      kind: :flash,
      sector: index,
      max: sector.light,
      min: Sectors.min_light(world, index),
      max_time: 64,
      min_time: 7,
      count: Bitwise.band(roll, 64) + 1
    })
  end

  @doc "Start a strobe in sector `index`: bright for a moment, dark for `dark` tics."
  @spec strobe(World.t(), non_neg_integer(), pos_integer(), boolean()) :: World.t()
  def strobe(world, index, dark, synced?) do
    sector = World.sector(world, index)
    min = Sectors.min_light(world, index)
    min = if min == sector.light, do: 0, else: min
    {roll, world} = World.random(world)
    count = if synced?, do: 1, else: Bitwise.band(roll, 7) + 1

    Machines.start(world, %{
      kind: :strobe,
      sector: index,
      min: min,
      max: sector.light,
      dark: dark,
      bright: @strobe_bright,
      count: count
    })
  end

  @doc "Start a glow in sector `index`, between its light and its dimmest neighbour's."
  @spec glow(World.t(), non_neg_integer()) :: World.t()
  def glow(world, index) do
    sector = World.sector(world, index)

    Machines.start(world, %{
      kind: :glow,
      sector: index,
      min: Sectors.min_light(world, index),
      max: sector.light,
      direction: -1
    })
  end

  @doc "Set the light of every sector tagged `tag`: a level, or `:max_neighbour` or `:min_neighbour`."
  @spec set_tagged(World.t(), integer(), integer() | :max_neighbour | :min_neighbour) :: World.t()
  def set_tagged(world, tag, level) do
    world
    |> Sectors.tagged(tag)
    |> Enum.reduce(world, fn index, acc ->
      World.update_sector(acc, index, &%{&1 | light: level_for(acc, index, level)})
    end)
  end

  defp level_for(world, index, :max_neighbour), do: Sectors.max_light(world, index)
  defp level_for(world, index, :min_neighbour), do: Sectors.min_light(world, index)
  defp level_for(_world, _index, level), do: level

  @doc "Start a slow strobe in every sector tagged `tag` that no mover has taken."
  @spec strobe_tagged(World.t(), integer()) :: World.t()
  def strobe_tagged(world, tag) do
    world
    |> Sectors.tagged(tag)
    |> Enum.reject(&Machines.busy?(world, &1))
    |> Enum.reduce(world, &strobe(&2, &1, 35, false))
  end

  @doc "One tic of `light`."
  @spec step(map(), pos_integer(), World.t()) :: {:keep, map(), World.t()}
  def step(%{kind: kind, count: count} = light, _id, world)
      when kind in [:flash, :strobe] and count > 1,
      do: {:keep, %{light | count: count - 1}, world}

  def step(%{kind: :flash} = light, _id, world) do
    {roll, world} = World.random(world)

    {level, count} =
      if World.sector(world, light.sector).light == light.max,
        do: {light.min, Bitwise.band(roll, light.min_time) + 1},
        else: {light.max, Bitwise.band(roll, light.max_time) + 1}

    {:keep, %{light | count: count}, set(world, light.sector, level)}
  end

  def step(%{kind: :strobe} = light, _id, world) do
    {level, count} =
      if World.sector(world, light.sector).light == light.min,
        do: {light.max, light.bright},
        else: {light.min, light.dark}

    {:keep, %{light | count: count}, set(world, light.sector, level)}
  end

  def step(%{kind: :glow} = glow, _id, world) do
    light = World.sector(world, glow.sector).light
    {level, direction} = glowing(glow, light)
    {:keep, %{glow | direction: direction}, set(world, glow.sector, level)}
  end

  defp glowing(%{direction: -1} = glow, light) when light - @glow_speed <= glow.min,
    do: {light, 1}

  defp glowing(%{direction: -1}, light), do: {light - @glow_speed, -1}

  defp glowing(%{direction: 1} = glow, light) when light + @glow_speed >= glow.max,
    do: {light, -1}

  defp glowing(%{direction: 1}, light), do: {light + @glow_speed, 1}

  defp set(world, index, level), do: World.update_sector(world, index, &%{&1 | light: level})
end
