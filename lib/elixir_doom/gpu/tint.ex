defmodule ElixirDoom.Gpu.Tint do
  @moduledoc """
  Doom's palette washes as the graphics card's screen tint: the display colour and
  strength `{r, g, b, a}` (`0..1`) that blending the finished frame's display colours
  towards gives the colours of palette `index` in place of palette `0`.

      ElixirDoom.Gpu.Tint.of(graphics, 3)

  The tint is fitted to the WAD's own palettes by least squares over all 256 colours,
  each channel's washed value a straight line of its plain value. Palette `0` is no tint.
  """

  alias ElixirDoom.Graphics

  @doc "The screen tint that stands for palette `index` of `graphics`."
  @spec of(Graphics.t(), 0..13) :: {float(), float(), float(), float()}
  def of(_graphics, 0), do: {0.0, 0.0, 0.0, 0.0}

  def of(graphics, index) do
    fits =
      Enum.zip_with(
        channels(Graphics.palette(graphics, 0)),
        channels(Graphics.palette(graphics, index)),
        &fit/2
      )

    strength = 1.0 - Enum.sum(Enum.map(fits, &elem(&1, 0))) / 3

    if strength <= 1.0e-3 do
      {0.0, 0.0, 0.0, 0.0}
    else
      [r, g, b] = Enum.map(fits, fn {_slope, intercept} -> clamp(intercept / strength) end)
      {r, g, b, strength}
    end
  end

  defp channels(palette) do
    entries = for <<r, g, b <- palette>>, do: {r / 255, g / 255, b / 255}
    for channel <- 0..2, do: Enum.map(entries, &elem(&1, channel))
  end

  defp fit(xs, ys) do
    count = length(xs)
    mean_x = Enum.sum(xs) / count
    mean_y = Enum.sum(ys) / count

    {covariance, variance} =
      xs
      |> Enum.zip(ys)
      |> Enum.reduce({0.0, 0.0}, fn {x, y}, {cov, var} ->
        {cov + (x - mean_x) * (y - mean_y), var + (x - mean_x) * (x - mean_x)}
      end)

    slope = if variance > 0, do: covariance / variance, else: 1.0
    {slope, mean_y - slope * mean_x}
  end

  defp clamp(value), do: value |> max(0.0) |> min(1.0)
end
