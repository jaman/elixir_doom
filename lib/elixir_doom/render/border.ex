defmodule ElixirDoom.Render.Border do
  @moduledoc """
  Doom's screen sizes: below size 10 the view is a smaller window centred in the space
  above the status bar, framed by the border flat and its bevelled edges.

      {left, top, inner_width, inner_height} = ElixirDoom.Render.Border.window(8, {640, 336})
      rgba = ElixirDoom.Render.Border.rgba(graphics, {640, 336}, {left, top, inner_width, inner_height}, palette)
  """

  alias Cauldron2D.Sectors.{Frame, Overlay}
  alias ElixirDoom.Graphics
  alias ElixirDoom.Render.Screens

  @doc "The view's window, `{left, top, width, height}`, inside a space `width` by `height` at screen size `blocks`."
  @spec window(integer(), {pos_integer(), pos_integer()}) ::
          {non_neg_integer(), non_neg_integer(), pos_integer(), pos_integer()}
  def window(blocks, {width, height}) when blocks >= 10, do: {0, 0, width, height}

  def window(blocks, {width, height}) do
    inner_width = max(round(width * blocks * 32 / 320), 8)

    inner_height =
      max(round(height * Bitwise.band(div(blocks * 168, 10), Bitwise.bnot(7)) / 168), 8)

    {div(width - inner_width, 2), div(height - inner_height, 2), inner_width, inner_height}
  end

  @doc "The border around `window` in a space `width` by `height`, as RGBA through `palette`."
  @spec rgba(Graphics.t(), {pos_integer(), pos_integer()}, tuple(), binary()) :: binary()
  def rgba(graphics, {width, height}, {left, top, inner_width, inner_height}, palette) do
    {sx, sy} = {width / 320, height / 168}
    {l, t, r, b} = {left / sx, top / sy, (left + inner_width) / sx, (top + inner_height) / sy}

    records =
      for {name, x, y} <- edges({l, t, r, b}),
          id = Graphics.patch(graphics, name),
          id != nil do
        info = Graphics.patch_info(graphics, name)

        Overlay.columns(
          graphics.pictures,
          id,
          {(x - info.left) * sx, (y - info.top) * sy, info.width * sx, info.height * sy},
          0
        )
      end

    graphics
    |> Screens.backdrop(flat(graphics), {width, height})
    |> Frame.columns(graphics.pictures, records)
    |> Frame.rgba(palette)
  end

  defp flat(graphics),
    do: if(Graphics.flat(graphics, "FLOOR7_2"), do: "FLOOR7_2", else: "GRNROCK")

  defp edges({l, t, r, b}) do
    across =
      for x <- Enum.take_every(trunc(l)..trunc(r - 8)//1, 8),
          edge <- [{"BRDR_T", x, t - 8}, {"BRDR_B", x, b}],
          do: edge

    down =
      for y <- Enum.take_every(trunc(t)..trunc(b - 8)//1, 8),
          edge <- [{"BRDR_L", l - 8, y}, {"BRDR_R", r, y}],
          do: edge

    across ++
      down ++
      [
        {"BRDR_TL", l - 8, t - 8},
        {"BRDR_TR", r, t - 8},
        {"BRDR_BL", l - 8, b},
        {"BRDR_BR", r, b}
      ]
  end
end
