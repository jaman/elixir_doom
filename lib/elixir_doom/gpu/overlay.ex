defmodule ElixirDoom.Gpu.Overlay do
  @moduledoc """
  Doom's 2D layer for the graphics card's picture, as RGBA `640` by `400` (Doom's 320 by
  200 screen twice over) to be stretched over the frame: during a level the weapon in
  hand, the border of a smaller view, the status bar, messages and the automap; between
  levels the tally and the closing text, opaque; and an open menu over all of it. Pixels
  nothing is drawn on are fully see-through.

      rgba = ElixirDoom.Gpu.Overlay.rgba(view, automap: false, seen_key: key, menu: nil, options: %{})

  The shimmering pictures of a partly invisible player's weapon are left to
  `ElixirDoom.Gpu.Weapon`. Takes the options of `ElixirDoom.Render.picture/4`.
  """

  alias Cauldron2D.Sectors.{Frame, Overlay}
  alias ElixirDoom.{Assets, Graphics, Layer, Render, StatusBar, Text}
  alias ElixirDoom.Render.{Automap, Border, Layout, Screens, Wash, Weapon}

  @size {640, 400}
  @clear <<0, 0, 0, 0>>

  @doc "The size of the overlay in pixels."
  @spec size() :: {pos_integer(), pos_integer()}
  def size, do: @size

  @doc "The overlay for `view` under `opts`, as RGBA."
  @spec rgba(map(), keyword()) :: binary()
  def rgba(view, opts) do
    graphics = Assets.get().graphics

    view
    |> layer(graphics, opts)
    |> Render.menu_over(@size, Keyword.get(opts, :menu), graphics)
  end

  defp layer(%{phase: :level, me: %{}} = view, graphics, opts), do: level(view, graphics, opts)

  defp layer(%{phase: :intermission} = view, graphics, _opts),
    do: Screens.intermission(view, graphics, @size).rgba

  defp layer(%{phase: phase}, graphics, _opts) when phase in [:finale, :over],
    do: Screens.finale(graphics, @size).rgba

  defp layer(_waiting, _graphics, _opts), do: Screens.blank(elem(@size, 0), elem(@size, 1)).rgba

  defp level(view, graphics, opts) do
    width = elem(@size, 0)
    layout = Layout.new(@size, opts)
    palette = Graphics.palette(graphics, Wash.palette_index(view.player))
    top = above_bar(view, graphics, layout, palette, Keyword.get(opts, :seen_key))

    bar =
      if layout.bar_height > 0,
        do:
          Frame.rgba(StatusBar.draw(Frame.new(width, layout.bar_height), graphics, view), palette),
        else: <<>>

    rgba = top <> bar

    if layout.options.messages,
      do:
        Layer.over(
          rgba,
          @size,
          palette,
          &Text.message(&1, graphics, view.player, {width, layout.view_height})
        ),
      else: rgba
  end

  defp above_bar(view, _graphics, %{automap: true} = layout, palette, key) do
    view
    |> Automap.frame({elem(@size, 0), layout.view_height}, key)
    |> Frame.rgba(palette)
  end

  defp above_bar(view, graphics, layout, palette, _key) do
    space = {elem(@size, 0), layout.view_height}
    window = Border.window(layout.blocks, space)

    weapon = weapon(graphics, view, window, palette)

    if window == {0, 0, elem(space, 0), elem(space, 1)},
      do: weapon,
      else: splice(Border.rgba(graphics, space, window, palette), weapon, elem(space, 0), window)
  end

  defp splice(under, over, width, {left, top, inner_width, inner_height}) do
    for y <- 0..(div(byte_size(under), width * 4) - 1), into: <<>> do
      row = binary_part(under, y * width * 4, width * 4)

      if y >= top and y < top + inner_height,
        do:
          binary_part(row, 0, left * 4) <>
            binary_part(over, (y - top) * inner_width * 4, inner_width * 4) <>
            binary_part(row, (left + inner_width) * 4, (width - left - inner_width) * 4),
        else: row
    end
  end

  defp weapon(graphics, view, {_left, _top, inner_width, inner_height}, palette) do
    window = {inner_width, inner_height}

    clear = :binary.copy(@clear, inner_width * inner_height)

    case graphics
         |> Weapon.sprites(view, window, Wash.fixed_table(view.player))
         |> Enum.reject(& &1.shimmer) do
      [] -> clear
      solid -> Layer.over(clear, window, palette, &columns(&1, graphics, solid))
    end
  end

  defp columns(frame, graphics, sprites) do
    records =
      for sprite <- sprites,
          do: Overlay.columns(graphics.pictures, sprite.picture, sprite.rect, sprite.light)

    Frame.columns(frame, graphics.pictures, records)
  end
end
