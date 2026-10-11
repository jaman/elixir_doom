defmodule Mix.Tasks.Doom do
  @shortdoc "Play Doom in this terminal"

  @moduledoc """
  Play a Doom WAD in the terminal.

      mix doom --wad DOOM1.WAD
      mix doom --wad DOOM1.WAD --level E1M3 --skill 4

  `--wad` defaults to `config :elixir_doom, :wad` (which `DOOM_WAD` sets), then the `DOOMWADDIR` directory's
  `DOOM1.WAD` or `DOOM.WAD`. `--skill` is `1` (I'm too young to die) to `5` (Nightmare),
  default `3`. `--level` defaults to the WAD's first. `--picture` (or `CAULDRON_PICTURE`) is how the picture
  reaches a terminal that keeps images, as `Cauldron2D.Drafter.Client.Picture` reads it:
  any of `native`, `native:N`, `size:WxH`, `png` and `swap`, comma separated, or
  `none`; default `native:2,swap`. `--mute` plays no sound
  (`CAULDRON_MUTE=1` too).
  """

  use Mix.Task
  alias Cauldron2D.Drafter.Client.Picture

  @switches [
    wad: :string,
    level: :string,
    skill: :integer,
    name: :string,
    picture: :string,
    mute: :boolean
  ]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: @switches)
    Mix.Task.run("app.start")
    path = Keyword.get(opts, :wad) || Application.get_env(:elixir_doom, :wad) || from_env()

    case path && ElixirDoom.Assets.load(path) do
      {:ok, _assets} -> play(opts)
      {:error, reason} -> Mix.raise("could not read #{path}: #{inspect(reason)}")
      nil -> Mix.raise("give a WAD: mix doom --wad path/to/DOOM1.WAD")
    end
  end

  defp from_env do
    with dir when is_binary(dir) <- System.get_env("DOOMWADDIR") do
      Enum.find(["DOOM1.WAD", "DOOM.WAD", "doom1.wad", "doom.wad"], fn name ->
        File.exists?(Path.join(dir, name))
      end)
      |> then(&(&1 && Path.join(dir, &1)))
    end
  end

  defp play(opts) do
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)

    Drafter.run(Cauldron2D.Drafter.Client,
      refresh_rate: "35fps",
      props: %{
        game: ElixirDoom.Client,
        username: Keyword.get(opts, :name, "marine"),
        level: Keyword.get(opts, :level),
        skill: Keyword.get(opts, :skill, 3),
        picture: picture(opts[:picture]),
        mute: opts[:mute]
      }
    )
  end

  defp picture(nil), do: nil

  defp picture(options) do
    case Picture.parse(options) do
      {:ok, options} -> options
      {:error, message} -> Mix.raise("--picture: " <> message)
    end
  end
end
