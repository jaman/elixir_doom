defmodule ElixirDoom.Render.Screens do
  @moduledoc """
  The pictures shown between levels and when nothing is in play: the tally after a
  level, the episode's closing text, a blank screen, and the backdrops they stand on.

      ElixirDoom.Render.Screens.intermission(view, graphics, {640, 400})
      ElixirDoom.Render.Screens.backdrop(graphics, "FLOOR4_8", {640, 400})

  Text and pictures keep Doom's 320 by 200 layout stretched to the size asked for.
  """

  alias Cauldron2D.Sectors.{Frame, Overlay}
  alias ElixirDoom.{Graphics, Text}
  alias FrenchCurve.Raster

  @finale [
    "ONCE YOU BEAT THE BIG BADASSES AND",
    "CLEAN OUT THE MOON BASE YOU'RE SUPPOSED",
    "TO WIN, AREN'T YOU? AREN'T YOU? WHERE'S",
    "YOUR FAT REWARD AND TICKET HOME? WHAT",
    "THE HELL IS THIS? IT'S NOT SUPPOSED TO",
    "END THIS WAY!",
    "",
    "THE EPISODE IS OVER. PRESS USE TO LEAVE."
  ]

  @doc "A black raster `width` by `height`."
  @spec blank(pos_integer(), pos_integer()) :: Raster.t()
  def blank(width, height),
    do: Raster.from_rgba(width, height, :binary.copy(<<0, 0, 0, 255>>, width * height))

  @doc "The tally of the level just finished, from an intermission view."
  @spec intermission(map(), Graphics.t(), {pos_integer(), pos_integer()}) :: Raster.t()
  def intermission(view, graphics, {width, height}) do
    tally = view.tally
    seconds = tally.seconds

    lines = [
      {"#{tally.level} FINISHED", 30},
      {"KILLS    #{percent(tally.kills, tally.kill_total)}", 70},
      {"ITEMS    #{percent(tally.items, tally.item_total)}", 90},
      {"SECRET   #{percent(tally.secrets, tally.secret_total)}", 110},
      {"TIME     #{div(seconds, 60)}:#{String.pad_leading(Integer.to_string(rem(seconds, 60)), 2, "0")}",
       140},
      {"PRESS USE OR FIRE", 180}
    ]

    lines
    |> Enum.reduce(backdrop(graphics, "WIMAP0", {width, height}), fn {text, y}, acc ->
      Text.draw(acc, graphics, text, {60, y}, {width / 320, height / 200}, 2)
    end)
    |> raster(graphics)
  end

  @doc "The episode's closing text."
  @spec finale(Graphics.t(), {pos_integer(), pos_integer()}) :: Raster.t()
  def finale(graphics, {width, height}) do
    @finale
    |> Enum.with_index()
    |> Enum.reduce(backdrop(graphics, "FLOOR4_8", {width, height}), fn {line, index}, acc ->
      Text.draw(acc, graphics, line, {10, 20 + index * 12}, {width / 320, height / 200}, 1)
    end)
    |> raster(graphics)
  end

  @doc "A frame `width` by `height` filled by patch `name` stretched over it, or flat `name` tiled across it."
  @spec backdrop(Graphics.t(), String.t(), {pos_integer(), pos_integer()}) :: Frame.t()
  def backdrop(graphics, name, {width, height}) do
    frame = Frame.fill(Frame.new(width, height), 0)

    cond do
      id = Graphics.patch(graphics, name) -> stretched(frame, graphics, id)
      id = Graphics.flat(graphics, name) -> tiled(frame, graphics, id)
      true -> frame
    end
  end

  defp percent(_got, total) when total <= 0, do: "100%"
  defp percent(got, total), do: "#{div(got * 100, total)}%"

  defp raster(frame, graphics),
    do:
      Raster.from_rgba(
        frame.width,
        frame.height,
        Frame.rgba(frame, Graphics.palette(graphics, 0))
      )

  defp stretched(frame, graphics, id),
    do:
      Frame.columns(
        frame,
        graphics.pictures,
        Overlay.columns(graphics.pictures, id, {0, 0, frame.width, frame.height}, 0)
      )

  defp tiled(frame, graphics, id) do
    tile = max(round(frame.width / 5), 8)

    records =
      for tx <- 0..div(frame.width, tile), ty <- 0..div(frame.height, tile) do
        Overlay.columns(graphics.pictures, id, {tx * tile, ty * tile, tile, tile}, 0)
      end

    Frame.columns(frame, graphics.pictures, records)
  end
end
