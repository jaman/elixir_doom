defmodule ElixirDoom.Client do
  @moduledoc """
  Doom as a `Cauldron2D.Client.Game`: the keys, the picture the terminal shows, the sound
  effects and the music.

      mix doom --wad DOOM1.WAD

  The whole pane is the game's own picture (`ElixirDoom.Render`), drawn at the pane's
  size in whatever the terminal shows best: images where it takes them, block glyphs
  elsewhere.

  ## Keys

    * `W`/`S` or `↑`/`↓` — forward and back; `A`/`D` — strafe; `←`/`→` — turn
    * `Space` — fire; `F` — use a door or switch
    * `R` — run while held; `Q`/`E` — previous and next weapon; `1`–`7` — a weapon
    * `Tab` — the automap; `Esc` — the menu

  `Esc` opens Doom's own menu (`ElixirDoom.Menu`), and the game pauses while it is open:
  new game (episode and skill), options (end game, messages, graphic detail, screen
  size, mouse sensitivity, sound and music volume, and controls, where keys and mouse
  buttons are bound and the mouse switched on), read this, and quit. With the mouse on,
  moving it left and right turns, the left button fires, the right button runs, and the
  wheel picks the previous and next weapon.

  ## Controller

    * left stick — forward, back and strafe; right stick — turn; each as far as it is
      pushed. The d-pad walks and turns at full speed
    * right trigger — fire; left trigger or pressing the left stick — run
    * `A` or `X` — use; the bumpers — previous and next weapon
    * `Back` — the automap; `Start` — the menu, where the d-pad moves, `A` chooses and
      `B` goes back
  """

  @behaviour Cauldron2D.Client.Game

  alias ElixirDoom.{Assets, Game, Menu, Render, Sounds, Wad, World}

  @atlas :elixir_doom

  @impl true
  def title, do: %{name: "DOOM", tagline: "in Elixir, in your terminal"}

  @impl true
  def atlas do
    unless Cauldron2D.Atlas.installed?(@atlas) do
      @atlas |> Cauldron2D.Atlas.new(tile: 16, void: {0, 0, 0}) |> Cauldron2D.Atlas.install()
    end

    @atlas
  end

  @impl true
  def actions do
    [
      :forward,
      :back,
      :turn_left,
      :turn_right,
      :strafe_left,
      :strafe_right,
      :run,
      :fire,
      :use,
      :next_weapon,
      :prev_weapon
    ] ++
      Enum.map(1..7, &:"weapon_#{&1}")
  end

  @impl true
  def keymaps do
    keys =
      Map.merge(
        %{
          forward: [:w, :up],
          back: [:s, :down],
          turn_left: [:left],
          turn_right: [:right],
          strafe_left: [:a],
          strafe_right: [:d],
          run: [:r],
          fire: [:" "],
          use: [:f],
          prev_weapon: [:q],
          next_weapon: [:e]
        },
        Map.new(1..7, &{:"weapon_#{&1}", [:"#{&1}"]})
      )

    mouse = %{
      turn_left: [{:mouse, :move_left}],
      turn_right: [{:mouse, :move_right}],
      run: [{:mouse, :right}],
      fire: [{:mouse, :left}],
      prev_weapon: [{:mouse, :wheel_up}],
      next_weapon: [{:mouse, :wheel_down}]
    }

    [keyboard: keys, mouse: Map.merge(keys, mouse, fn _action, key, button -> key ++ button end)]
  end

  @impl true
  def padmap(_props) do
    %{
      forward: [:dpad_up, {:axis, :left_y, :neg}],
      back: [:dpad_down, {:axis, :left_y, :pos}],
      strafe_left: [{:axis, :left_x, :neg}],
      strafe_right: [{:axis, :left_x, :pos}],
      turn_left: [:dpad_left, {:axis, :right_x, :neg}],
      turn_right: [:dpad_right, {:axis, :right_x, :pos}],
      fire: [{:axis, :right_trigger, :pos}],
      run: [{:axis, :left_trigger, :pos}, :left_stick],
      use: [:a, :x],
      prev_weapon: [:left_bumper],
      next_weapon: [:right_bumper]
    }
  end

  @impl true
  def client_pad do
    %{
      {:look, :automap} => :back,
      menu: :start,
      settings: nil,
      projection: nil,
      turn_left: nil,
      turn_right: nil
    }
  end

  @impl true
  def toggles, do: []

  @impl true
  def holds do
    for action <- [
          :forward,
          :back,
          :turn_left,
          :turn_right,
          :strafe_left,
          :strafe_right,
          :run,
          :fire
        ],
        do: {action, 160}
  end

  @impl true
  def client_keys do
    %{
      {:look, :automap} => [:tab],
      menu: :escape,
      back: nil,
      settings: nil,
      settings_menu: nil,
      title: nil,
      talk: nil,
      watch: nil,
      team: nil,
      chat: nil,
      guide: nil,
      projection: nil,
      turn_left: nil,
      turn_right: nil,
      tilt_up: nil,
      tilt_down: nil,
      zoom_in: nil,
      zoom_out: nil,
      zoom_reset: nil
    }
  end

  @impl true
  def options, do: Menu.defaults()

  @impl true
  def open_menu(settings), do: Menu.open(settings)

  @impl true
  def menu_event(menu, event, settings), do: Menu.event(menu, event, settings)

  @impl true
  def input_options(options), do: [gesture_ms: 60 + Map.get(options, :mouse_sensitivity, 5) * 20]

  @impl true
  def start, do: {:play, :doom}

  @impl true
  def look,
    do: %{
      projection: :picture,
      projections: [:picture],
      automap: false,
      native: {320, 200},
      picture: [{:native, 2}, :swap]
    }

  @impl true
  def chat?, do: false

  @impl true
  def lobby?, do: false

  @impl true
  def worlds(props) do
    game_opts = [level: Map.get(props, :level), skill: Map.get(props, :skill, 3)]

    [
      %{
        id: :doom,
        name: "Doom",
        world: {Game, [hz: 35, game_opts: game_opts]},
        players: 0,
        humans: []
      }
    ]
  end

  @impl true
  def scene(view), do: scene(view, look())

  @impl true
  def scene(view, look) do
    key = view_key(view)

    %{
      focus: {0.0, 0.0},
      bounds: :unbounded,
      cell: fn _cell -> nil end,
      movers: [],
      picture: fn size, aspect ->
        Render.picture(view, size, aspect,
          automap: Map.get(look, :automap, false),
          seen_key: key,
          menu: Map.get(look, :menu),
          options: Map.get(look, :options, %{})
        )
      end
    }
  end

  defp view_key(%{level: level}), do: {self(), level}
  defp view_key(_view), do: nil

  @impl true
  def hud(_view), do: []

  @impl true
  def listener(%{phase: :level, me: %{x: x, y: y}}),
    do: {x / World.audio_scale(), y / World.audio_scale()}

  def listener(_view), do: nil

  @impl true
  def sounds do
    fn
      {:sound, name} -> Sounds.voice(name)
      _other -> nil
    end
  end

  @impl true
  def music do
    case music_sections() do
      sections when map_size(sections) == 0 ->
        []

      sections ->
        [
          {"doom",
           %{
             bpm: 60,
             beats_per_bar: 4,
             layers: [:track],
             sections: sections,
             fingerprint: sections |> :erlang.phash2() |> Integer.to_string()
           }}
        ]
    end
  end

  defp music_sections do
    if Assets.loaded?() do
      assets = Assets.get()

      for level <- assets.levels,
          lump = Wad.lump(assets.wad, "D_" <> level),
          lump != nil,
          {:ok, midi} <- [TuningFork.Mus.parse(lump)],
          into: %{},
          do: {level, %{track: TuningFork.Gm.score(midi)}}
    else
      %{}
    end
  end

  @impl true
  def cue(%{phase: :level, level: level}, :play),
    do: %{piece: "doom", section: level, layers: %{track: 1.0}}

  def cue(_view, _screen), do: nil

  @impl true
  def outcome(%{phase: :over}),
    do: %{title: "THE EPISODE IS OVER", lines: ["Thanks for playing."], next: :lobby}

  def outcome(_view), do: nil
end
