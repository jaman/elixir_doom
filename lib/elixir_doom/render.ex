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

  alias Cauldron2D.Sectors.{Automap, Frame, Light, Overlay, View}
  alias ElixirDoom.{Assets, Graphics, Layer, Menu, Seen, StatusBar, Text}
  alias FrenchCurve.Raster

  @doc "Draw `view` as a raster `width` by `height`, with the options above."
  @spec picture(map(), {pos_integer(), pos_integer()}, number(), keyword()) :: Raster.t()
  def picture(view, {width, height}, aspect, opts \\ []) do
    graphics = Assets.get().graphics
    width = max(width, 32)
    height = max(height, 20)

    raster =
      case view do
        %{phase: :level, me: %{}} -> level(view, graphics, {width, height}, aspect, opts)
        %{phase: :intermission} -> intermission(view, graphics, {width, height})
        %{phase: phase} when phase in [:finale, :over] -> finale(view, graphics, {width, height})
        _waiting -> blank(width, height)
      end

    menu(raster, Keyword.get(opts, :menu), graphics)
  end

  defp menu(raster, nil, _graphics), do: raster

  defp menu(raster, menu, graphics) do
    seconds = System.monotonic_time(:millisecond) / 1000
    size = {raster.width, raster.height}

    rgba =
      Layer.over(
        raster.rgba,
        size,
        Graphics.palette(graphics, 0),
        &Menu.Draw.draw(&1, menu, graphics, seconds)
      )

    Raster.from_rgba(raster.width, raster.height, rgba)
  end

  defp blank(width, height),
    do: Raster.from_rgba(width, height, :binary.copy(<<0, 0, 0, 255>>, width * height))

  defp level(view, graphics, {width, height}, aspect, opts) do
    options = Map.merge(Menu.defaults(), Keyword.get(opts, :options, %{}))

    blocks =
      if Keyword.get(opts, :automap, false),
        do: max(options.screen_blocks, 10),
        else: options.screen_blocks

    bar_height = if blocks >= 11, do: 0, else: max(round(height * 32 / 200), 8)
    view_height = height - bar_height
    palette = Graphics.palette(graphics, palette_index(view.player))
    key = Keyword.get(opts, :seen_key)

    screen =
      if Keyword.get(opts, :automap, false),
        do: Frame.rgba(automap(view, graphics, {width, view_height}, key), palette),
        else:
          framed(
            view,
            graphics,
            {width, view_height},
            aspect,
            key,
            {blocks, options.detail},
            palette
          )

    bar =
      if bar_height > 0,
        do: Frame.rgba(StatusBar.draw(Frame.new(width, bar_height), graphics, view), palette),
        else: <<>>

    rgba = screen <> bar

    rgba =
      if options.messages,
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
    {left, top, inner_width, inner_height} = window(blocks, {width, height})
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
          border(graphics, {width, height}, {left, top, inner_width, inner_height}, palette),
          world,
          {width, left, top, inner_width, inner_height}
        )
  end

  defp window(blocks, {width, height}) when blocks >= 10, do: {0, 0, width, height}

  defp window(blocks, {width, height}) do
    inner_width = max(round(width * blocks * 32 / 320), 8)

    inner_height =
      max(round(height * Bitwise.band(div(blocks * 168, 10), Bitwise.bnot(7)) / 168), 8)

    {div(width - inner_width, 2), div(height - inner_height, 2), inner_width, inner_height}
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

  defp border(graphics, {width, height}, {left, top, inner_width, inner_height}, palette) do
    frame =
      backdrop(
        graphics,
        if(Graphics.flat(graphics, "FLOOR7_2"), do: "FLOOR7_2", else: "GRNROCK"),
        {width, height}
      )

    {sx, sy} = {width / 320, height / 168}
    {l, t, r, b} = {left / sx, top / sy, (left + inner_width) / sx, (top + inner_height) / sy}

    edges =
      for(
        x <- Enum.take_every(trunc(l)..trunc(r - 8)//1, 8),
        do: [{"BRDR_T", x, t - 8}, {"BRDR_B", x, b}]
      ) ++
        for(
          y <- Enum.take_every(trunc(t)..trunc(b - 8)//1, 8),
          do: [{"BRDR_L", l - 8, y}, {"BRDR_R", r, y}]
        ) ++
        [
          [
            {"BRDR_TL", l - 8, t - 8},
            {"BRDR_TR", r, t - 8},
            {"BRDR_BL", l - 8, b},
            {"BRDR_BR", r, b}
          ]
        ]

    records =
      for {name, x, y} <- List.flatten(edges), id = Graphics.patch(graphics, name), id != nil do
        info = Graphics.patch_info(graphics, name)

        Overlay.columns(
          graphics.pictures,
          id,
          {(x - info.left) * sx, (y - info.top) * sy, info.width * sx, info.height * sy},
          0
        )
      end

    frame |> Frame.columns(graphics.pictures, records) |> Frame.rgba(palette)
  end

  defp world(view, graphics, {width, height}, aspect, key) do
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

    {:ok, level} = Assets.level(view.level)
    fixed = fixed_table(view.player)

    eye = %{
      x: view.eye.x,
      y: view.eye.y,
      z: view.eye.z,
      angle: view.eye.angle,
      sectors: view.sectors,
      sides: view.sides,
      things: view.things
    }

    %{frame: frame, seen: seen} =
      View.render(Frame.new(width, height), graphics.pictures, level.map, eye,
        sky: sky_spec,
        stretch: stretch,
        contrast: 16,
        extra_light: view.player.extra_light * 16,
        fixed: fixed
      )

    if key, do: Seen.add(key, seen)
    weapon(frame, graphics, view, {width, height}, fixed)
  end

  defp fixed_table(player) do
    invulnerable = Map.get(player.powers, :invulnerability, 0)
    infrared = Map.get(player.powers, :infrared, 0)

    cond do
      invulnerable > 4 * 32 or (Bitwise.band(invulnerable, 8) != 0 and invulnerable > 0) -> 32
      infrared > 4 * 32 or (Bitwise.band(infrared, 8) != 0 and infrared > 0) -> 1
      true -> nil
    end
  end

  defp weapon(frame, graphics, view, {width, height}, fixed) do
    player = view.player
    scale_x = width / 320
    scale_y = height / 168
    sector_light = elem(view.sectors, view.me.sector).light
    base = max(Light.start(sector_light + player.extra_light * 16) - 23, 0)

    shadow? =
      Map.get(player.powers, :invisibility, 0) > 4 * 32 or
        Bitwise.band(Map.get(player.powers, :invisibility, 0), 8) != 0

    records =
      for slot <- [:weapon, :flash],
          sprite = Map.fetch!(player, slot),
          sprite.state != nil,
          state = ElixirDoom.Info.state(sprite.state),
          {name, frame_index, bright} = state.picture,
          {id, _flip, lump} <- List.wrap(Graphics.sprite(graphics, name, frame_index, 0)),
          info = Graphics.patch_info(graphics, lump) do
        light =
          cond do
            fixed -> fixed
            bright -> 0
            true -> base
          end

        x = (sprite.sx - info.left) * scale_x
        y = (sprite.sy - info.top - 16) * scale_y

        Overlay.columns(
          graphics.pictures,
          id,
          {x, y, info.width * scale_x, info.height * scale_y},
          if(shadow? and not bright, do: 6, else: light),
          shimmer: shadow? and not bright
        )
      end

    Frame.columns(frame, graphics.pictures, records)
  end

  defp palette_index(player) do
    strength = Map.get(player.powers, :strength, 0)
    berserk = if strength > 0, do: 12 - div(strength, 64), else: 0
    count = max(player.damage_count, berserk)
    ironfeet = Map.get(player.powers, :ironfeet, 0)

    cond do
      count > 0 -> min(div(count + 7, 8), 7) + 1
      player.bonus_count > 0 -> min(div(player.bonus_count + 7, 8), 3) + 9
      ironfeet > 4 * 32 or (Bitwise.band(ironfeet, 8) != 0 and ironfeet > 0) -> 13
      true -> 0
    end
  end

  defp automap(view, _graphics, {width, height}, key) do
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

    colours = %{wall: 176, floor_step: 64, ceiling_step: 231, unseen: 99}
    lines = Automap.lines(level.map, view.sectors, seen, camera, colours, all: all?)

    Frame.new(width, height)
    |> Frame.fill(0)
    |> Frame.lines(lines ++ Automap.arrow(camera, 209))
  end

  defp intermission(view, graphics, {width, height}) do
    tally = view.tally
    frame = backdrop(graphics, "WIMAP0", {width, height})
    percent = fn got, total -> if total > 0, do: "#{div(got * 100, total)}%", else: "100%" end
    seconds = tally.seconds

    lines = [
      {"#{tally.level} FINISHED", 30},
      {"KILLS    #{percent.(tally.kills, tally.kill_total)}", 70},
      {"ITEMS    #{percent.(tally.items, tally.item_total)}", 90},
      {"SECRET   #{percent.(tally.secrets, tally.secret_total)}", 110},
      {"TIME     #{div(seconds, 60)}:#{String.pad_leading(Integer.to_string(rem(seconds, 60)), 2, "0")}",
       140},
      {"PRESS USE OR FIRE", 180}
    ]

    frame =
      Enum.reduce(lines, frame, fn {text, y}, acc ->
        Text.draw(acc, graphics, text, {60, y}, {width / 320, height / 200}, 2)
      end)

    Raster.from_rgba(width, height, Frame.rgba(frame, Graphics.palette(graphics, 0)))
  end

  defp finale(_view, graphics, {width, height}) do
    frame = backdrop(graphics, "FLOOR4_8", {width, height})

    text = [
      "ONCE YOU BEAT THE BIG BADASSES AND",
      "CLEAN OUT THE MOON BASE YOU'RE SUPPOSED",
      "TO WIN, AREN'T YOU? AREN'T YOU? WHERE'S",
      "YOUR FAT REWARD AND TICKET HOME? WHAT",
      "THE HELL IS THIS? IT'S NOT SUPPOSED TO",
      "END THIS WAY!",
      "",
      "THE EPISODE IS OVER. PRESS USE TO LEAVE."
    ]

    frame =
      text
      |> Enum.with_index()
      |> Enum.reduce(frame, fn {line, index}, acc ->
        Text.draw(acc, graphics, line, {10, 20 + index * 12}, {width / 320, height / 200}, 1)
      end)

    Raster.from_rgba(width, height, Frame.rgba(frame, Graphics.palette(graphics, 0)))
  end

  defp backdrop(graphics, name, {width, height}) do
    frame = Frame.fill(Frame.new(width, height), 0)

    cond do
      id = Graphics.patch(graphics, name) -> stretched(frame, graphics, id)
      id = Graphics.flat(graphics, name) -> tiled(frame, graphics, id)
      true -> frame
    end
  end

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
