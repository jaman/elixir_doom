defmodule ElixirDoom.Specials.Switches do
  @moduledoc """
  Switches: the texture on a used line flips to its pair, and a switch that can be used
  again flips back a second later. A line that works once is marked used.

  `step/3` is a `Cauldron2D.Thinkers` step for a `:button`, the timer that flips a switch
  back.
  """

  alias ElixirDoom.{Assets, World}
  alias ElixirDoom.Specials.Machines

  @button_time 35

  @doc """
  Flip the switch on line `index`, used by thing `actor_id`. `repeat?` starts the timer
  that flips it back; otherwise the line is marked used. `exit?` makes the exit sound.
  """
  @spec flip(World.t(), non_neg_integer(), boolean(), boolean(), term()) :: World.t()
  def flip(world, index, repeat?, exit?, actor_id) do
    line = elem(world.map.lines, index)
    side = elem(world.sides, line.front)
    switches = Assets.get().switches

    case Enum.find([:upper, :middle, :lower], &Map.has_key?(switches, Map.get(side, &1))) do
      nil ->
        mark_used(world, index, not repeat?)

      where ->
        flip_texture(
          world,
          {index, line.front, where},
          Map.get(side, where),
          {repeat?, exit?, actor_id}
        )
    end
  end

  defp flip_texture(world, {index, side, where}, original, {repeat?, exit?, actor_id}) do
    world = set_texture(world, side, where, Map.fetch!(Assets.get().switches, original))
    at = World.mobj(world, actor_id) || %{x: 0.0, y: 0.0}
    world = World.sound(world, if(exit?, do: "DSSWTCHX", else: "DSSWTCHN"), at)

    if repeat? do
      Machines.start(world, %{
        kind: :button,
        side: side,
        where: where,
        texture: original,
        timer: @button_time,
        at: {at.x, at.y}
      })
    else
      mark_used(world, index, true)
    end
  end

  @doc "Mark line `index` used, so it does nothing again, when `once?`."
  @spec mark_used(World.t(), non_neg_integer(), boolean()) :: World.t()
  def mark_used(world, _index, false), do: world
  def mark_used(world, index, true), do: %{world | used: MapSet.put(world.used, index)}

  @doc "One tic of a switch's timer; when it runs out the switch flips back."
  @spec step(map(), pos_integer(), World.t()) :: {:keep, map(), World.t()} | {:done, World.t()}
  def step(%{timer: timer} = button, _id, world) when timer > 1,
    do: {:keep, %{button | timer: timer - 1}, world}

  def step(button, _id, world) do
    world = set_texture(world, button.side, button.where, button.texture)
    {:done, World.sound(world, "DSSWTCHN", button.at)}
  end

  defp set_texture(world, side, where, texture),
    do: %{
      world
      | sides: put_elem(world.sides, side, Map.put(elem(world.sides, side), where, texture))
    }
end
