defmodule ElixirDoom.Specials.Ceilings do
  @moduledoc """
  Starting ceilings and crushers by tag, stopping crushers, and starting stopped ones
  again.

  Kinds: `:lower_to_floor`, `:lower_and_crush`, `:raise_to_highest`, and the crushers
  `:crush_and_raise`, `:fast_crush_and_raise` and `:silent_crush_and_raise`.
  """

  alias ElixirDoom.Specials.{Machines, Sectors}
  alias ElixirDoom.World

  @crushers [:crush_and_raise, :fast_crush_and_raise, :silent_crush_and_raise]

  @doc "Start `type` in every sector tagged `tag` that no mover has taken: `{world, started?}`."
  @spec by_tag(World.t(), integer(), atom()) :: {World.t(), boolean()}
  def by_tag(world, tag, type) do
    world = if type in @crushers, do: wake(world, tag), else: world

    world
    |> Sectors.tagged(tag)
    |> Enum.reject(&Machines.busy?(world, &1))
    |> Enum.reduce({world, false}, fn sector, {acc, _started?} ->
      {Machines.start_mover(acc, sector, mover(acc, tag, sector, type)), true}
    end)
  end

  defp mover(world, tag, index, type) do
    sector = World.sector(world, index)

    base = %{
      kind: :ceiling,
      type: type,
      sector: index,
      tag: tag,
      crush: false,
      speed: 1.0,
      status: :moving,
      top: sector.ceiling,
      bottom: sector.floor
    }

    Map.merge(base, plan(world, index, sector, type))
  end

  defp plan(_world, _index, sector, :fast_crush_and_raise),
    do: %{crush: true, bottom: sector.floor + 8, direction: -1, speed: 2.0}

  defp plan(_world, _index, sector, type)
       when type in [:crush_and_raise, :silent_crush_and_raise],
       do: %{crush: true, bottom: sector.floor + 8, direction: -1}

  defp plan(_world, _index, sector, :lower_and_crush),
    do: %{bottom: sector.floor + 8, direction: -1}

  defp plan(_world, _index, sector, :lower_to_floor), do: %{bottom: sector.floor, direction: -1}

  defp plan(world, index, _sector, :raise_to_highest),
    do: %{top: Sectors.highest_ceiling(world, index), direction: 1}

  @doc "Stop every crusher tagged `tag` where it is."
  @spec stop(World.t(), integer()) :: World.t()
  def stop(world, tag),
    do:
      Machines.update_where(
        world,
        &match?(%{kind: :ceiling, tag: ^tag}, &1),
        &%{&1 | status: :stasis}
      )

  defp wake(world, tag) do
    Machines.update_where(
      world,
      &match?(%{kind: :ceiling, tag: ^tag, status: :stasis}, &1),
      &%{&1 | status: :moving}
    )
  end
end
