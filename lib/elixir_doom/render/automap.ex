defmodule ElixirDoom.Render.Automap do
  @moduledoc """
  The automap: the lines of the level the player has seen (all of them with the computer
  map), drawn around the player's arrow on black.

      frame = ElixirDoom.Render.Automap.frame(view, {640, 336}, seen_key)
  """

  alias Cauldron2D.Sectors.{Automap, Frame}
  alias ElixirDoom.{Assets, Seen}

  @colours %{wall: 176, floor_step: 64, ceiling_step: 231, unseen: 99}
  @arrow 209

  @doc "The automap of a level view, `width` by `height`, from the lines seen under `key`."
  @spec frame(map(), {pos_integer(), pos_integer()}, term()) :: Frame.t()
  def frame(view, {width, height}, key) do
    {:ok, level} = Assets.level(view.level)
    seen = if key, do: Seen.get(key), else: MapSet.new()
    all? = Map.get(view.player.powers, :allmap, 0) > 0

    camera = %{
      x: view.me.x,
      y: view.me.y,
      angle: view.me.angle,
      scale: width / 1600,
      center: {width / 2, height / 2}
    }

    lines = Automap.lines(level.map, view.sectors, seen, camera, @colours, all: all?)

    Frame.new(width, height)
    |> Frame.fill(0)
    |> Frame.lines(lines ++ Automap.arrow(camera, @arrow))
  end
end
