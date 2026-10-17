defmodule ElixirDoom.Render do
  @moduledoc """
  A player's view drawn as a picture of any size: the level through
  `Cauldron2D.Sectors.View`, the weapon in hand, messages, the status bar along the
  bottom, the automap when it is open, the screen's red and gold flashes, and the
  tallies between levels.

      ElixirDoom.Render.picture(view, {320, 200}, 1.0, automap: false)

  The picture keeps Doom's layout at any size: the bottom 32 of every 200 rows are the
  status bar, and everything in it, the weapon and the messages are Doom's 320 by 200
  screen stretched to fit. `aspect` is a pixel's width against its height on screen.

  ## Options

    * `:automap`, `:seen_key` — the automap open, and the key its seen lines are kept under
    * `:options` — the player's options (`ElixirDoom.Menu.defaults/0`): `:screen_blocks`
      3 to 11 as Doom's screen size (below 10 a smaller view framed by the border flat
      and its edges, 11 no status bar), `:detail` `:high` or `:low` (the view drawn half
      as wide and doubled), `:messages` whether pickup messages show
    * `:menu` — an open `ElixirDoom.Menu`, drawn over the picture
  """

  alias Cauldron2D.Sectors.{Frame, View}
  alias ElixirDoom.{Assets, Graphics, Layer, Menu, Seen, StatusBar, Text}
  alias ElixirDoom.Render.{Automap, Border, Layout, Screens, Wash, Weapon}
  alias FrenchCurve.Raster

  @doc "Draw `view` as a raster `width` by `height`, with the options above."
  @spec picture(map(), {pos_integer(), pos_integer()}, number(), keyword()) :: Raster.t()
  def picture(view, {width, height}, aspect, opts \\ []) do
    graphics = Assets.get().graphics
    width = max(width, 32)
    height = max(height, 20)

    raster =
      case view do
        %{phase: :level, me: %{}} ->
          level(view, graphics, {width, height}, aspect, opts)

        %{phase: :intermission} ->
          Screens.intermission(view, graphics, {width, height})

        %{phase: phase} when phase in [:finale, :over] ->
          Screens.finale(graphics, {width, height})

        _waiting ->
          Screens.blank(width, height)
      end

    menu(raster, Keyword.get(opts, :menu), graphics)
  end

  @doc "`rgba` (`width` by `height`) with an open `menu` drawn over it, or as it is when `menu` is `nil`."
  @spec menu_over(binary(), {pos_integer(), pos_integer()}, Menu.t() | nil, Graphics.t()) ::
          binary()
  def menu_over(rgba, _size, nil, _graphics), do: rgba

  def menu_over(rgba, size, menu, graphics) do
    seconds = System.monotonic_time(:millisecond) / 1000

    Layer.over(
      rgba,
      size,
      Graphics.palette(graphics, 0),
      &Menu.Draw.draw(&1, menu, graphics, seconds)
    )
  end

  defp menu(raster, menu, graphics) do
    size = {raster.width, raster.height}
    Raster.from_rgba(raster.width, raster.height, menu_over(raster.rgba, size, menu, graphics))
  end

  defp level(view, graphics, {width, height}, aspect, opts) do
    layout = Layout.new({width, height}, opts)
    view_height = layout.view_height
    palette = Graphics.palette(graphics, Wash.palette_index(view.player))
    key = Keyword.get(opts, :seen_key)

    screen =
      if layout.automap,
        do: Frame.rgba(Automap.frame(view, {width, view_height}, key), palette),
        else:
          framed(
            view,
            graphics,
            {width, view_height},
            aspect,
            key,
            {layout.blocks, layout.options.detail},
            palette
          )

    bar =
      if layout.bar_height > 0,
        do:
          Frame.rgba(
            StatusBar.draw(Frame.new(width, layout.bar_height), graphics, view),
            palette
          ),
        else: <<>>

    rgba = screen <> bar

    rgba =
      if layout.options.messages,
        do:
          Layer.over(
            rgba,
            {width, height},
            palette,
            &Text.message(&1, graphics, view.player, {width, view_height})
          ),
        else: rgba

    Raster.from_rgba(width, height, rgba)
  end

  defp framed(view, graphics, {width, height}, aspect, key, {blocks, detail}, palette) do
    {left, top, inner_width, inner_height} = window = Border.window(blocks, {width, height})
    drawn_width = if detail == :low, do: max(div(inner_width, 2), 1), else: inner_width
    drawn_aspect = if detail == :low, do: aspect * inner_width / drawn_width, else: aspect

    world =
      view
      |> world(graphics, {drawn_width, inner_height}, drawn_aspect, key)
      |> Frame.rgba(palette)

    world =
      if drawn_width == inner_width,
        do: world,
        else: widen(world, drawn_width, inner_width, inner_height)

    if inner_width == width and inner_height == height,
      do: world,
      else:
        splice(
          Border.rgba(graphics, {width, height}, window, palette),
          world,
          {width, left, top, inner_width, inner_height}
        )
  end

  defp widen(rgba, from, to, rows) do
    columns = for x <- 0..(to - 1), do: min(div(x * from, to), from - 1)

    for y <- 0..(rows - 1), into: <<>> do
      row = binary_part(rgba, y * from * 4, from * 4)
      for x <- columns, into: <<>>, do: binary_part(row, x * 4, 4)
    end
  end

  defp splice(under, over, {width, left, top, inner_width, inner_height}) do
    for y <- 0..(div(byte_size(under), width * 4) - 1), into: <<>> do
      row = binary_part(under, y * width * 4, width * 4)

      if y >= top and y < top + inner_height do
        inside = binary_part(over, (y - top) * inner_width * 4, inner_width * 4)

        binary_part(row, 0, left * 4) <>
          inside <> binary_part(row, (left + inner_width) * 4, (width - left - inner_width) * 4)
      else
        row
      end
    end
  end

  defp world(view, graphics, {width, height}, aspect, key) do
    fixed = Wash.fixed_table(view.player)

    %{frame: frame, seen: seen} =
      View.render(
        Frame.new(width, height),
        graphics.pictures,
        level_map(view),
        eye(view),
        view_options(view, graphics, width, aspect, fixed)
      )

    if key, do: Seen.add(key, seen)
    Weapon.draw(frame, graphics, view, {width, height}, fixed)
  end

  @doc """
  The lines of the level `view` sees, recorded under `key` for the automap, as a view
  `width` by `height` drawn with `aspect` would see them.
  """
  @spec record_seen(map(), term(), {pos_integer(), pos_integer()}, number()) :: :ok
  def record_seen(_view, nil, _size, _aspect), do: :ok

  def record_seen(view, key, {width, height}, aspect) do
    graphics = Assets.get().graphics

    %{seen: seen} =
      View.render(
        Frame.new(width, height),
        graphics.pictures,
        level_map(view),
        Map.put(eye(view), :things, []),
        view_options(view, graphics, width, aspect, Wash.fixed_table(view.player))
      )

    Seen.add(key, seen)
  end

  defp level_map(view) do
    {:ok, level} = Assets.level(view.level)
    level.map
  end

  defp eye(view) do
    %{
      x: view.eye.x,
      y: view.eye.y,
      z: view.eye.z,
      angle: view.eye.angle,
      sectors: view.sectors,
      sides: view.sides,
      things: view.things
    }
  end

  defp view_options(view, graphics, width, aspect, fixed) do
    sky = Graphics.wall(graphics, view.sky)
    stretch = 1.2 * aspect

    sky_spec =
      if sky do
        %{
          picture: sky,
          flat: Graphics.flat(graphics, "F_SKY1"),
          columns: 1024 / (2 * :math.pi()),
          mid: 100.0,
          step: 320 / (width * stretch)
        }
      end

    [
      sky: sky_spec,
      stretch: stretch,
      contrast: 16,
      extra_light: view.player.extra_light * 16,
      fixed: fixed
    ]
  end
end
