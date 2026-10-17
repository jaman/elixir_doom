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
        else: merge(under, row_a, row_b, colours, [])
    end
  end

  defp merge(<<>>, <<>>, <<>>, _colours, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp merge(
         <<pixel::binary-4, under::binary>>,
         <<0, row_a::binary>>,
         <<255, row_b::binary>>,
         colours,
         acc
       ),
       do: merge(under, row_a, row_b, colours, [pixel | acc])

  defp merge(
         <<_pixel::binary-4, under::binary>>,
         <<a, row_a::binary>>,
         <<b, row_b::binary>>,
         colours,
         acc
       ),
       do: merge(under, row_a, row_b, colours, [drawn(colours, a, b) | acc])

  defp drawn(colours, a, 255), do: elem(colours, a)
  defp drawn(colours, _a, b), do: elem(colours, b)
end
