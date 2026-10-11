defmodule ElixirDoom.Layer do
  @moduledoc """
  Drawing over a finished picture: whatever a function draws onto a frame the picture's
  size is laid over the picture's RGBA, every other pixel left as it was. The function
  is run on two frames of different colours, so a pixel it drew is known whatever colour
  it drew in. Rows it drew nothing on are copied whole.

      ElixirDoom.Layer.over(rgba, {width, height}, palette, &ElixirDoom.Text.draw(&1, ...))
  """

  alias Cauldron2D.Sectors.Frame

  @doc "`rgba` (`width` by `height`) with what `draw` draws laid over it, through `palette`."
  @spec over(binary(), {pos_integer(), pos_integer()}, binary(), (Frame.t() -> Frame.t())) ::
          binary()
  def over(rgba, {width, height}, palette, draw) do
    a = width |> Frame.new(height) |> Frame.fill(0) |> draw.() |> Frame.pixels()
    b = width |> Frame.new(height) |> Frame.fill(255) |> draw.() |> Frame.pixels()
    colours = List.to_tuple(for <<r, g, bl <- palette>>, do: <<r, g, bl, 255>>)
    blank_a = :binary.copy(<<0>>, width)
    blank_b = :binary.copy(<<255>>, width)

    for y <- 0..(height - 1), into: <<>> do
      under = binary_part(rgba, y * width * 4, width * 4)
      row_a = binary_part(a, y * width, width)
      row_b = binary_part(b, y * width, width)

      if row_a == blank_a and row_b == blank_b,
        do: under,
        else: merge(under, row_a, row_b, colours)
    end
  end

  defp merge(under, row_a, row_b, colours) do
    pixels = for <<pixel::binary-4 <- under>>, do: pixel

    [pixels, :binary.bin_to_list(row_a), :binary.bin_to_list(row_b)]
    |> Enum.zip_with(fn
      [pixel, 0, 255] -> pixel
      [_pixel, a, 255] -> elem(colours, a)
      [_pixel, _a, b] -> elem(colours, b)
    end)
    |> IO.iodata_to_binary()
  end
end
