defmodule ElixirDoom.Text do
  @moduledoc """
  Writing in Doom's small font (`STCFN033`..`STCFN095`) onto a frame, placed in Doom's
  320 by 200 screen and stretched to the frame, and the message line a player sees after
  picking something up.
  """

  alias Cauldron2D.Sectors.{Frame, Overlay}
  alias ElixirDoom.Graphics

  @space 4

  @doc "Write `text` at `{x, y}` in Doom's screen, scaled by `{sx, sy}` and enlarged `size` times."
  @spec draw(
          Frame.t(),
          Graphics.t(),
          String.t(),
          {number(), number()},
          {number(), number()},
          number()
        ) ::
          Frame.t()
  def draw(frame, graphics, text, {x, y}, {sx, sy}, size \\ 1) do
    {records, _x} =
      text
      |> String.upcase()
      |> String.to_charlist()
      |> Enum.reduce({[], x}, fn char, {acc, at} ->
        case glyph(graphics, char) do
          nil ->
            {acc, at + @space * size}

          {id, info} ->
            rect =
              {at * sx, (y - info.top * size) * sy, info.width * size * sx,
               info.height * size * sy}

            {[Overlay.columns(graphics.pictures, id, rect, 0) | acc], at + info.width * size}
        end
      end)

    Frame.columns(frame, graphics.pictures, Enum.reverse(records))
  end

  @doc "How wide `text` is in Doom's screen pixels, enlarged `size` times."
  @spec width(Graphics.t(), String.t(), number()) :: number()
  def width(graphics, text, size \\ 1) do
    text
    |> String.upcase()
    |> String.to_charlist()
    |> Enum.reduce(0, fn char, acc ->
      case glyph(graphics, char) do
        nil -> acc + @space * size
        {_id, info} -> acc + info.width * size
      end
    end)
  end

  defp glyph(graphics, char) when char in 33..95 do
    name = "STCFN" <> String.pad_leading(Integer.to_string(char), 3, "0")

    case Graphics.patch(graphics, name) do
      nil -> nil
      id -> {id, Graphics.patch_info(graphics, name)}
    end
  end

  defp glyph(_graphics, _char), do: nil

  @doc "The player's current message across the top of a view `width` by `height`."
  @spec message(Frame.t(), Graphics.t(), map(), {pos_integer(), pos_integer()}) :: Frame.t()
  def message(frame, graphics, %{message: text, message_tics: tics}, {width, height})
      when tics > 0 and is_binary(text),
      do: draw(frame, graphics, text, {1, 1}, {width / 320, height / 168})

  def message(frame, _graphics, _player, _size), do: frame
end
