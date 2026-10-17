defmodule Mix.Tasks.Doom do
  @shortdoc "Play Doom in this terminal"

  @moduledoc """
  Play a Doom WAD in the terminal.

      mix doom
      mix doom --wad DOOM1.WAD --level E1M3 --skill 4

  The first run opens a setup page (`Cauldron2D.Drafter.Launcher`). There you pick the
  WAD, the skill and how the game is drawn. Play saves your choices, and later runs
  start straight away with them. The page also opens when the saved WAD is gone, or when
  you pass `--launcher`. When nothing is saved yet, a WAD is looked for in `DOOMWADDIR`,
  Steam's Doom folders and the system's games folders first.

  Flags change one run without changing what is saved:

    * `--wad` — the game WAD; `DOOM_WAD` or `config :elixir_doom, :wad` too
    * `--level` — the level to start on; default the WAD's first
    * `--skill` — `1` (I'm too young to die) to `5` (Nightmare!)
    * `--software`, `--gpu`, `--window` — draw without the graphics card, with it in the
      terminal, or with it in a window of its own whose keys play the game. Without
      these the saved drawing choice is used; its default draws on the graphics card
      when there is one.
    * `--picture` (or `CAULDRON_PICTURE`) — how pictures reach a terminal that keeps
      images, as `Cauldron2D.Drafter.Client.Picture` reads it; default `native:2,swap`
    * `--mute` — no sound (`CAULDRON_MUTE=1` too)
    * `--name` — the player name settings are kept under; default `marine`
  """

  use Mix.Task
  alias Cauldron2D.Drafter.Client.Picture
  alias Cauldron2D.Drafter.Launcher

  @switches [
    wad: :string,
    level: :string,
    skill: :integer,
    name: :string,
    picture: :string,
    gpu: :boolean,
    window: :boolean,
    software: :boolean,
    launcher: :boolean,
    mute: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: @switches)
    Mix.Task.run("app.start")
    name = Keyword.get(opts, :name, "marine")

    overrides =
      %{
        wad: Keyword.get(opts, :wad) || Application.get_env(:elixir_doom, :wad),
        skill: opts[:skill]
      }
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    case Launcher.choose(ElixirDoom.Client, fields(),
           overrides: overrides,
           launcher: Keyword.get(opts, :launcher, false),
           player: name
         ) do
      {:ok, values} -> start(opts, name, values)
      :quit -> :ok
    end
  end

  defp fields do
    [
      %{
        key: :wad,
        label: "Game WAD",
        kind: {:path, &ElixirDoom.Assets.check/1},
        discover: &ElixirDoom.Assets.discover/0,
        hint: "DOOM.WAD, DOOM1.WAD (shareware), DOOM2.WAD or a Freedoom WAD"
      },
      %{
        key: :skill,
        label: "Skill",
        kind:
          {:choice,
           [
             {1, "I'm too young to die"},
             {2, "Hey, not too rough"},
             {3, "Hurt me plenty"},
             {4, "Ultra-Violence"},
             {5, "Nightmare!"}
           ]},
        default: 3
      },
      Launcher.drawing_field()
    ]
  end

  defp start(opts, name, values) do
    case ElixirDoom.Assets.load(values.wad) do
      {:ok, _assets} -> play(opts, name, values)
      {:error, reason} -> Mix.raise("could not read #{values.wad}: #{inspect(reason)}")
    end
  end

  defp play(opts, name, values) do
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

    Drafter.run(Cauldron2D.Drafter.Client,
      refresh_rate: "35fps",
      props: %{
        game: ElixirDoom.Client,
        username: name,
        level: Keyword.get(opts, :level),
        skill: values.skill,
        picture: opts[:picture] |> picture() |> card(opts),
        mute: opts[:mute]
      }
    )
  end

  defp card(options, opts) do
    added = for switch <- [:gpu, :window, :software], opts[switch], do: switch

    case added do
      [] -> options
      _ -> (options || ElixirDoom.Client.look().picture) ++ added
    end
  end

  defp picture(nil), do: nil

  defp picture(options) do
    case Picture.parse(options) do
      {:ok, options} -> options
      {:error, message} -> Mix.raise("--picture: " <> message)
    end
  end
end
