defmodule ElixirDoom.Menu do
  @moduledoc """
  Doom's menus, as the player moves through them: main, episode, skill, options, sound
  volume, controls, the read-this screens, and Doom's messages that wait for a key or for
  y or n.

      menu = ElixirDoom.Menu.open(settings)
      %{menu: menu, settings: settings, sounds: sounds} = ElixirDoom.Menu.event(menu, {:key, :down}, settings)

  `event/3` returns what `Cauldron2D.Client.Game`'s `menu_event/3` returns, the menu
  holding the settings it shows (`:settings`). The options live in the settings: key
  bindings, the sound and music volumes, and under `:options` messages on or off,
  `:high` or `:low` detail, the screen size in Doom's blocks (3 to 11) and the mouse
  sensitivity (0 to 9). A new game is sent to the world as the request
  `{:new_game, episode, skill}` (skill 1 to 5); ending the game or quitting leaves it.
  An episode the WAD lacks answers with Doom's shareware message; loading and saving
  answer that they are not part of this game.
  """

  alias Cauldron2D.Input
  alias ElixirDoom.Assets

  defstruct page: :main,
            cursor: %{main: 0, episode: 0, skill: 2, options: 0, sound: 0, controls: 0},
            grab?: false,
            message: nil,
            settings: %{}

  @type t :: %__MODULE__{}

  @quit [
    "are you sure you want to\nquit this great game?",
    "please don't leave, there's more\ndemons to toast!",
    "let's beat it -- this is turning\ninto a bloodbath!",
    "i wouldn't leave if i were you.\ndos is much worse.",
    "you're trying to say you like dos\nbetter than me, right?",
    "don't leave yet -- there's a\ndemon around that corner!",
    "ya know, next time you come in here\ni'm gonna toast ya.",
    "go ahead and leave. see if i care."
  ]

  @quit_sounds ~w(DSPLDETH DSDMPAIN DSPOPAIN DSSLOP DSTELEPT DSPOSIT1 DSPOSIT3 DSSGTATK)

  @controls [
    {"use mouse", :mouse},
    {"fire", :fire},
    {"use", :use},
    {"forward", :forward},
    {"back", :back},
    {"turn left", :turn_left},
    {"turn right", :turn_right},
    {"strafe left", :strafe_left},
    {"strafe right", :strafe_right},
    {"run", :run},
    {"next weapon", :next_weapon},
    {"previous weapon", :prev_weapon}
  ]

  @items %{
    main: [:new_game, :options, :load, :save, :read_this, :quit],
    episode: [1, 2, 3, 4],
    skill: [1, 2, 3, 4, 5],
    options: [:end_game, :messages, :detail, :screen_size, nil, :mouse, nil, :sound, :controls],
    sound: [:sfx, nil, :music, nil]
  }

  @doc "The player options and their defaults, as Doom starts."
  @spec defaults() :: map()
  def defaults, do: %{messages: true, detail: :high, screen_blocks: 10, mouse_sensitivity: 5}

  @doc "The rows of a page: an item, or `nil` for the slider beneath the one above it."
  @spec items(atom()) :: [term()]
  def items(page), do: Map.get(@items, page, [])

  @doc "The controls page's rows, as `{name, action}`; `:mouse` is the use-mouse switch."
  @spec controls() :: [{String.t(), atom()}]
  def controls, do: @controls

  @doc "The menu as Escape opens it: the main menu."
  @spec open(map()) :: t()
  def open(settings), do: %__MODULE__{settings: settings}

  @doc "Whether the mouse is bound to anything in `settings`."
  @spec mouse?(map()) :: boolean()
  def mouse?(settings),
    do:
      Enum.any?(settings.bindings, fn {_action, keys} ->
        Enum.any?(keys, &match?({:mouse, _}, &1))
      end)

  @doc "Take one event; see the module documentation for what comes back."
  @spec event(t(), term(), map()) :: map()
  def event(%__MODULE__{grab?: true} = menu, event, settings), do: grab(menu, event, settings)

  def event(%__MODULE__{message: %{}} = menu, event, settings),
    do: answer(menu, key_of(event), settings)

  def event(%__MODULE__{} = menu, event, settings) do
    case key_of(event) do
      nil -> stay(menu, settings)
      key -> page(menu.page, key, menu, settings)
    end
  end

  defp key_of({:key, key}), do: key
  defp key_of({:key, key, _mods}), do: key
  defp key_of(_event), do: nil

  defp page(:main, key, _menu, settings) when key in [:escape, :backspace],
    do: %{menu: nil, settings: settings, sounds: [sound("DSSWTCHX")]}

  defp page(page, key, menu, settings) when key in [:escape, :backspace],
    do: stay(%{menu | page: parent(page)}, settings, "DSSWTCHX")

  defp page(page, key, menu, settings) when page in [:read1, :read2] and key == :enter,
    do: stay(%{menu | page: if(page == :read1, do: :read2, else: :main)}, settings, "DSPISTOL")

  defp page(page, :up, menu, settings)
       when page in [:main, :episode, :skill, :options, :sound, :controls],
       do: move(menu, page, -1, settings)

  defp page(page, :down, menu, settings)
       when page in [:main, :episode, :skill, :options, :sound, :controls],
       do: move(menu, page, 1, settings)

  defp page(:main, :enter, menu, settings),
    do: main(Enum.at(items(:main), menu.cursor.main), menu, settings)

  defp page(:episode, :enter, menu, settings),
    do: episode(menu.cursor.episode + 1, menu, settings)

  defp page(:skill, :enter, menu, settings), do: skill(menu.cursor.skill + 1, menu, settings)

  defp page(:options, key, menu, settings) when key in [:enter, :left, :right],
    do: option(Enum.at(items(:options), menu.cursor.options), key, menu, settings)

  defp page(:sound, key, menu, settings) when key in [:enter, :left, :right],
    do: volume(Enum.at(items(:sound), menu.cursor.sound), key, menu, settings)

  defp page(:controls, :enter, menu, settings),
    do: control(Enum.at(@controls, menu.cursor.controls), menu, settings)

  defp page(:controls, key, menu, settings) when key in [:backspace, :delete] do
    case Enum.at(@controls, menu.cursor.controls) do
      {_name, :mouse} ->
        stay(menu, settings)

      {_name, action} ->
        stay(menu, %{settings | bindings: Map.put(settings.bindings, action, [])}, "DSPISTOL")
    end
  end

  defp page(_page, _key, menu, settings), do: stay(menu, settings)

  defp parent(page) when page in [:episode], do: :main
  defp parent(:skill), do: :episode
  defp parent(page) when page in [:sound, :controls], do: :options
  defp parent(_page), do: :main

  defp move(menu, page, step, settings) do
    rows = if page == :controls, do: @controls, else: items(page)
    count = if page == :episode, do: episodes(), else: length(rows)
    cursor = next_row(rows, Map.fetch!(menu.cursor, page), step, count)
    stay(%{menu | cursor: Map.put(menu.cursor, page, cursor)}, settings, "DSPSTOP")
  end

  defp next_row(rows, at, step, count) do
    next = Integer.mod(at + step, count)
    if Enum.at(rows, next) == nil, do: next_row(rows, next, step, count), else: next
  end

  @doc "How many episodes the episode menu lists: four where the WAD has a fourth's title, else three."
  @spec episodes() :: 3..4
  def episodes do
    if Assets.loaded?() and ElixirDoom.Graphics.patch(Assets.get().graphics, "M_EPI4") != nil,
      do: 4,
      else: 3
  end

  defp main(:new_game, menu, settings), do: stay(%{menu | page: :episode}, settings, "DSPISTOL")
  defp main(:options, menu, settings), do: stay(%{menu | page: :options}, settings, "DSPISTOL")
  defp main(:read_this, menu, settings), do: stay(%{menu | page: :read1}, settings, "DSPISTOL")

  defp main(item, menu, settings) when item in [:load, :save],
    do:
      message(
        menu,
        settings,
        "loading and saving are not part\nof this game.\n\npress a key.",
        :key,
        :main
      )

  defp main(:quit, menu, settings) do
    text = Enum.random(@quit) <> "\n\n(press y to quit to dos.)"
    message(menu, settings, text, {:yes, :quit}, :main)
  end

  defp episode(n, menu, settings) do
    if Assets.loaded?() and "E#{n}M1" in Assets.get().levels,
      do: stay(%{menu | page: :skill}, settings, "DSPISTOL"),
      else:
        message(
          menu,
          settings,
          "this is the shareware version of doom.\n\nyou need to order the entire trilogy.\n\npress a key.",
          :key,
          :episode
        )
  end

  defp skill(5, menu, settings),
    do:
      message(
        menu,
        settings,
        "are you sure? this skill level\nisn't even remotely fair.\n\npress y or n.",
        {:yes, {:start, 5}},
        :skill
      )

  defp skill(skill, menu, settings), do: start(menu.cursor.episode + 1, skill, settings)

  defp start(episode, skill, settings),
    do: %{
      menu: nil,
      settings: settings,
      request: {:new_game, episode, skill},
      sounds: [sound("DSPISTOL")]
    }

  defp option(:end_game, :enter, menu, settings),
    do:
      message(
        menu,
        settings,
        "are you sure you want to end the game?\n\npress y or n.",
        {:yes, :leave},
        :options
      )

  defp option(:messages, _key, menu, s),
    do: stay(menu, put_option(s, :messages, not s.options.messages), "DSPISTOL")

  defp option(:detail, _key, menu, s),
    do:
      stay(
        menu,
        put_option(s, :detail, if(s.options.detail == :high, do: :low, else: :high)),
        "DSPISTOL"
      )

  defp option(:screen_size, key, menu, s),
    do:
      stay(
        menu,
        put_option(s, :screen_blocks, step(s.options.screen_blocks, key, 3, 11)),
        "DSSTNMOV"
      )

  defp option(:mouse, key, menu, s),
    do:
      stay(
        menu,
        put_option(s, :mouse_sensitivity, step(s.options.mouse_sensitivity, key, 0, 9)),
        "DSSTNMOV"
      )

  defp option(:sound, :enter, menu, settings),
    do: stay(%{menu | page: :sound}, settings, "DSPISTOL")

  defp option(:controls, :enter, menu, settings),
    do: stay(%{menu | page: :controls}, settings, "DSPISTOL")

  defp option(_item, _key, menu, settings), do: stay(menu, settings)

  defp volume(:sfx, key, menu, s) when key in [:left, :right],
    do: stay(menu, %{s | sfx: step(round(s.sfx * 15), key, 0, 15) / 15}, "DSSTNMOV")

  defp volume(:music, key, menu, s) when key in [:left, :right],
    do: stay(menu, %{s | music: step(round(s.music * 15), key, 0, 15) / 15}, "DSSTNMOV")

  defp volume(_item, _key, menu, settings), do: stay(menu, settings)

  defp step(value, :left, low, _high), do: max(value - 1, low)
  defp step(value, _key, _low, high), do: min(value + 1, high)

  defp put_option(settings, key, value),
    do: %{settings | options: Map.put(settings.options, key, value)}

  defp control({_name, :mouse}, menu, settings),
    do: stay(menu, use_mouse(settings, not mouse?(settings)), "DSPISTOL")

  defp control({_name, _action}, menu, settings),
    do: stay(%{menu | grab?: true}, settings, "DSPISTOL")

  defp use_mouse(settings, true) do
    mouse = Keyword.fetch!(ElixirDoom.Client.keymaps(), :mouse)

    added =
      Map.new(mouse, fn {action, keys} ->
        {action,
         Enum.uniq(
           Map.get(settings.bindings, action, []) ++ Enum.filter(keys, &match?({:mouse, _}, &1))
         )}
      end)

    %{settings | preset: :mouse, bindings: Map.merge(settings.bindings, added)}
  end

  defp use_mouse(settings, false) do
    bindings =
      Map.new(settings.bindings, fn {action, keys} ->
        {action, Enum.reject(keys, &match?({:mouse, _}, &1))}
      end)

    %{settings | preset: :keyboard, bindings: bindings}
  end

  defp grab(menu, event, settings) do
    case {key_of(event), Input.spec_of(event)} do
      {:escape, _} ->
        stay(%{menu | grab?: false}, settings, "DSSWTCHX")

      {_, nil} ->
        stay(menu, settings)

      {_, spec} ->
        stay(%{menu | grab?: false}, bind(settings, menu.cursor.controls, spec), "DSPISTOL")
    end
  end

  defp bind(settings, cursor, spec) do
    {_name, action} = Enum.at(@controls, cursor)
    freed = Map.new(settings.bindings, fn {other, keys} -> {other, List.delete(keys, spec)} end)
    %{settings | bindings: Map.update(freed, action, [spec], &(&1 ++ [spec]))}
  end

  defp message(menu, settings, text, wants, back),
    do: stay(%{menu | message: %{text: text, wants: wants}, page: back}, settings, "DSSWTCHN")

  defp answer(menu, nil, settings), do: stay(menu, settings)

  defp answer(%{message: %{wants: :key}} = menu, _key, settings),
    do: stay(%{menu | message: nil}, settings, "DSSWTCHX")

  defp answer(%{message: %{wants: {:yes, what}}} = menu, :y, settings),
    do: yes(what, menu, settings)

  defp answer(menu, _key, settings), do: stay(%{menu | message: nil}, settings, "DSSWTCHX")

  defp yes(:quit, _menu, settings),
    do: %{menu: nil, settings: settings, leave: true, sounds: [sound(Enum.random(@quit_sounds))]}

  defp yes(:leave, _menu, settings), do: %{menu: nil, settings: settings, leave: true}
  defp yes({:start, skill}, menu, settings), do: start(menu.cursor.episode + 1, skill, settings)

  defp stay(menu, settings), do: %{menu: %{menu | settings: settings}, settings: settings}

  defp stay(menu, settings, name),
    do: %{menu: %{menu | settings: settings}, settings: settings, sounds: [sound(name)]}

  defp sound(name), do: {:sound, name}
end
