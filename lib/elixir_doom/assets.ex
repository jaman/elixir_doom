defmodule ElixirDoom.Assets do
  @moduledoc """
  The WAD a game is played from, read once and shared by every process: its pictures,
  levels, sounds and music, and the tables derived from them.

      ElixirDoom.Assets.load("DOOM1.WAD")
      ElixirDoom.Assets.get().graphics
      ElixirDoom.Assets.level("E1M1")

  `load/1` reads the WAD, builds the pictures and installs everything under a
  `:persistent_term` key; `get/0` reads it back from any process. Levels are read the
  first time they are asked for and kept.
  """

  alias Cauldron2D.Drafter.Launcher
  alias ElixirDoom.{Graphics, Level, Tables, Wad}

  @key {__MODULE__, :assets}

  @enforce_keys [:wad, :graphics, :switches, :animations, :levels]
  defstruct [:wad, :graphics, :switches, :animations, :levels, :path]

  @type t :: %__MODULE__{
          wad: Wad.t(),
          graphics: Graphics.t(),
          switches: %{non_neg_integer() => non_neg_integer()},
          animations: [tuple()],
          levels: [String.t()],
          path: Path.t()
        }

  @wad_names ~w(DOOM.WAD DOOM1.WAD DOOM2.WAD doom.wad doom1.wad doom2.wad freedoom1.wad freedoom2.wad)
  @system_folders ["/usr/share/games/doom", "/usr/local/share/games/doom", "/usr/share/doom"]

  @doc "`:ok` when `path` is an IWAD (a whole game's WAD), else `{:error, text}` for a person to read."
  @spec check(Path.t()) :: :ok | {:error, String.t()}
  def check(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 4)) do
      {:ok, "IWAD"} ->
        :ok

      {:ok, _other} ->
        {:error, "not a Doom game WAD (DOOM.WAD, DOOM1.WAD, DOOM2.WAD or Freedoom)"}

      {:error, _reason} ->
        {:error, "no file here"}
    end
  end

  @doc """
  A game WAD in the usual places that `check/1` accepts, or `nil`: `DOOMWADDIR`,
  Steam's Ultimate Doom and Doom II folders, and the system's games folders.
  """
  @spec discover() :: Path.t() | nil
  def discover do
    steam =
      for game <- ["Ultimate Doom", "DOOM", "Doom 2"],
          folder <- Launcher.steam_folders(game),
          sub <- ["base", "rerelease", ""],
          do: Path.join(folder, sub)

    folders = List.wrap(System.get_env("DOOMWADDIR")) ++ steam ++ @system_folders

    Enum.find_value(folders, fn folder ->
      @wad_names
      |> Enum.map(&Path.join(folder, &1))
      |> Enum.find(&(check(&1) == :ok))
    end)
  end

  @doc "Read the WAD at `path` and install it. Gives the assets, or the reason it could not."
  @spec load(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def load(path, opts \\ []) do
    with {:ok, wad} <- Wad.open(path) do
      graphics = Graphics.load(wad, opts)

      assets = %__MODULE__{
        wad: wad,
        graphics: graphics,
        switches: switches(graphics),
        animations: animations(graphics),
        levels: Wad.levels(wad),
        path: path
      }

      :persistent_term.put(@key, assets)
      {:ok, assets}
    end
  end

  @doc "The installed assets; raises when none are."
  @spec get() :: t()
  def get do
    case :persistent_term.get(@key, nil) do
      nil -> raise ArgumentError, "no WAD loaded; call ElixirDoom.Assets.load/1 first"
      assets -> assets
    end
  end

  @doc "Whether a WAD is loaded."
  @spec loaded?() :: boolean()
  def loaded?, do: :persistent_term.get(@key, nil) != nil

  @doc "Level `name`, read on first use and kept."
  @spec level(String.t()) :: {:ok, Level.t()} | {:error, term()}
  def level(name) do
    key = {__MODULE__, :level, name}

    case :persistent_term.get(key, nil) do
      nil ->
        assets = get()

        with {:ok, level} <- Level.load(assets.wad, assets.graphics, name) do
          :persistent_term.put(key, level)
          {:ok, level}
        end

      level ->
        {:ok, level}
    end
  end

  @doc "The picture each animated picture shows at tic `tic`, for those that have moved on."
  @spec animation_frame(t(), non_neg_integer()) :: %{non_neg_integer() => non_neg_integer()}
  def animation_frame(%__MODULE__{animations: animations}, tic) do
    step = div(tic, 8)

    for sequence <- animations,
        count = tuple_size(sequence),
        index <- 0..(count - 1),
        into: %{},
        do: {elem(sequence, index), elem(sequence, rem(index + step, count))}
  end

  defp switches(graphics) do
    for {on, off} <- Tables.switches(),
        a = Graphics.wall(graphics, on),
        b = Graphics.wall(graphics, off),
        a != nil and b != nil,
        pair <- [{a, b}, {b, a}],
        into: %{},
        do: pair
  end

  defp animations(graphics) do
    flats =
      for names <- Tables.animated_flats(),
          ids = names |> Enum.map(&Graphics.flat(graphics, &1)) |> Enum.reject(&is_nil/1),
          length(ids) > 1,
          do: List.to_tuple(ids)

    walls =
      for names <- Tables.animated_walls(),
          ids = names |> Enum.map(&Graphics.wall(graphics, &1)) |> Enum.reject(&is_nil/1),
          length(ids) > 1,
          do: List.to_tuple(ids)

    flats ++ walls
  end
end
