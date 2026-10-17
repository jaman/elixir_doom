defmodule ElixirDoom.Menu.Draw do
  @moduledoc """
  Doom's menus drawn as Doom draws them, from the WAD's own pictures at Doom's positions
  in its 320 by 200 screen, stretched to the frame and kept above the status bar: the
  title, the items (the options raised to make room for the controls), the blinking
  skull, the sliders, the on and off switches, the read-this screens, the controls in
  Doom's small font, and Doom's messages centred on the screen.

      ElixirDoom.Menu.Draw.draw(frame, menu, graphics, seconds)
  """

  alias Cauldron2D.Sectors.{Frame, Overlay}
  alias ElixirDoom.{Graphics, Menu, Text}

  @line 16
  @options_top 24
  @controls_top 32
  @controls_line 10

  @doc "`menu` drawn onto `frame` at `time` seconds, for the skull's blinking."
  @spec draw(Frame.t(), Menu.t(), Graphics.t(), number()) :: Frame.t()
  def draw(frame, %Menu{message: %{text: text}}, graphics, _time),
    do: message(frame, graphics, text)

  def draw(frame, %Menu{} = menu, graphics, time) do
    scale = {frame.width / 320, frame.height / 200}
    {records, texts} = page(menu.page, menu, graphics, time)

    frame
    |> Frame.columns(graphics.pictures, Enum.map(records, &record(graphics, &1, scale)))
    |> write(graphics, texts, scale)
  end

  defp page(:main, menu, _graphics, time) do
    items = ~w(M_NGAME M_OPTION M_LOADG M_SAVEG M_RDTHIS M_QUITG)

    {[{"M_DOOM", 94, 2} | listed(items, {97, 64})] ++ [skull({97, 64}, menu.cursor.main, time)],
     []}
  end

  defp page(:episode, menu, _graphics, time) do
    items = Enum.map(1..Menu.episodes(), &"M_EPI#{&1}")

    {[{"M_EPISOD", 54, 38} | listed(items, {48, 63})] ++
       [skull({48, 63}, menu.cursor.episode, time)], []}
  end

  defp page(:skill, menu, _graphics, time) do
    items = ~w(M_JKILL M_ROUGH M_HURT M_ULTRA M_NMARE)

    {[{"M_NEWG", 96, 14}, {"M_SKILL", 54, 38} | listed(items, {48, 63})] ++
       [skull({48, 63}, menu.cursor.skill, time)], []}
  end

  defp page(:options, menu, _graphics, time) do
    s = menu.settings.options
    top = @options_top
    items = ["M_ENDGAM", "M_MESSG", "M_DETAIL", "M_SCRNSZ", nil, "M_MSENS", nil, "M_SVOL"]

    pictures =
      [{"M_OPTTTL", 108, 4} | listed(items, {60, top})] ++
        [
          {if(s.messages, do: "M_MSGON", else: "M_MSGOFF"), 60 + 120, top + @line},
          {if(s.detail == :high, do: "M_GDHIGH", else: "M_GDLOW"), 60 + 175, top + @line * 2}
        ] ++
        thermo({60, top + @line * 4}, 9, s.screen_blocks - 3) ++
        thermo({60, top + @line * 6}, 10, s.mouse_sensitivity) ++
        [skull({60, top}, menu.cursor.options, time)]

    drawing = "DRAWING  " <> drawing_text(Map.get(menu.settings, :drawing, :auto))

    {pictures,
     [{"CONTROLS", {62, top + @line * 8 + 3}, 2}, {drawing, {62, top + @line * 9 + 3}, 2}]}
  end

  defp page(:sound, menu, _graphics, time) do
    s = menu.settings

    pictures =
      [{"M_SVOL", 60, 38} | listed(["M_SFXVOL", nil, "M_MUSVOL", nil], {80, 64})] ++
        thermo({80, 64 + @line}, 16, round(s.sfx * 15)) ++
        thermo({80, 64 + @line * 3}, 16, round(s.music * 15)) ++
        [skull({80, 64}, menu.cursor.sound, time)]

    {pictures, []}
  end

  defp page(:controls, menu, _graphics, time) do
    rows =
      Menu.controls()
      |> Enum.with_index()
      |> Enum.flat_map(fn {{name, action}, i} ->
        y = @controls_top + i * @controls_line
        [{name, {48, y}, 1}, {value(menu.settings, action), {168, y}, 1}]
      end)

    marker =
      if menu.grab?, do: "=", else: if(rem(trunc(time * 35 / 8), 2) == 0, do: ">", else: "")

    footer =
      if menu.grab?,
        do: "press a key or button for this action",
        else: "enter to change, backspace to clear"

    {[],
     [
       {"CONTROLS", {104, 10}, 2},
       {marker, {36, @controls_top + menu.cursor.controls * @controls_line}, 1},
       {footer, {24, 156}, 1} | rows
     ]}
  end

  defp page(:read1, _menu, _graphics, _time), do: {[{:full, "HELP2"}], []}
  defp page(:read2, _menu, _graphics, _time), do: {[{:full, "HELP1"}], []}

  defp drawing_text(:auto), do: "AUTO"
  defp drawing_text(:software), do: "SOFTWARE"
  defp drawing_text(:pane), do: "CARD"
  defp drawing_text(:window), do: "WINDOW"

  defp value(settings, :mouse), do: if(Menu.mouse?(settings), do: "on", else: "off")
  defp value(settings, action), do: keys_text(Map.get(settings.bindings, action, []))

  defp listed(items, {x, y}) do
    for {name, i} <- Enum.with_index(items), name != nil, do: {name, x, y + i * @line}
  end

  defp skull({x, y}, item, time) do
    name = if rem(trunc(time * 35 / 8), 2) == 0, do: "M_SKULL1", else: "M_SKULL2"
    {name, x - 32, y - 5 + item * @line}
  end

  defp thermo({x, y}, width, dot) do
    middle = for i <- 0..(width - 1), do: {"M_THERMM", x + 8 + i * 8, y}

    [{"M_THERML", x, y} | middle] ++
      [{"M_THERMR", x + 8 + width * 8, y}, {"M_THERMO", x + 8 + dot * 8, y}]
  end

  defp record(graphics, {:full, name}, {sx, sy}) do
    case Graphics.patch(graphics, name) do
      nil -> []
      id -> Overlay.columns(graphics.pictures, id, {0.0, 0.0, 320 * sx, 200 * sy}, 0)
    end
  end

  defp record(graphics, {name, x, y}, {sx, sy}) do
    case Graphics.patch(graphics, name) do
      nil ->
        []

      id ->
        info = Graphics.patch_info(graphics, name)

        Overlay.columns(
          graphics.pictures,
          id,
          {(x - info.left) * sx, (y - info.top) * sy, info.width * sx, info.height * sy},
          0
        )
    end
  end

  defp write(frame, graphics, texts, scale) do
    Enum.reduce(texts, frame, fn {text, at, size}, acc ->
      Text.draw(acc, graphics, text, at, scale, size)
    end)
  end

  defp message(frame, graphics, text) do
    scale = {frame.width / 320, frame.height / 200}
    lines = String.split(text, "\n")
    top = 100 - div(length(lines) * 8, 2)

    lines
    |> Enum.with_index()
    |> Enum.reduce(frame, fn {line, i}, acc ->
      x = div(320 - trunc(Text.width(graphics, line)), 2)
      Text.draw(acc, graphics, line, {x, top + i * 8}, scale)
    end)
  end

  @names %{
    up: "UPARROW",
    down: "DOWNARROW",
    left: "LEFTARROW",
    right: "RIGHTARROW",
    " ": "SPACE",
    enter: "ENTER",
    tab: "TAB",
    page_up: "PGUP",
    page_down: "PGDN",
    home: "HOME",
    end: "END",
    delete: "DEL"
  }

  @mouse %{
    left: "MOUSE1",
    right: "MOUSE2",
    middle: "MOUSE3",
    wheel_up: "MWHEELUP",
    wheel_down: "MWHEELDOWN",
    move_left: "MOUSELEFT",
    move_right: "MOUSERIGHT",
    move_up: "MOUSEUP",
    move_down: "MOUSEDOWN"
  }

  defp keys_text([]), do: "---"
  defp keys_text([one]), do: key_name(one)
  defp keys_text([one, two | _]), do: key_name(one) <> " or " <> key_name(two)

  defp key_name({:mouse, button}), do: Map.get(@mouse, button, "MOUSE")

  defp key_name({key, mods}),
    do: Enum.map_join(mods, "+", &String.upcase(Atom.to_string(&1))) <> "+" <> key_name(key)

  defp key_name(key) when is_atom(key),
    do: Map.get(@names, key) || String.upcase(Atom.to_string(key))
end
