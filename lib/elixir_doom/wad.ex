defmodule ElixirDoom.Wad do
  @moduledoc """
  A Doom WAD file: its lumps by name and in order.

      {:ok, wad} = ElixirDoom.Wad.open("DOOM1.WAD")
      ElixirDoom.Wad.lump(wad, "PLAYPAL")
      ElixirDoom.Wad.between(wad, "S_START", "S_END")

  The whole file is read into memory once. Names are upper case, at most eight
  characters. Where several lumps share a name — a level's `THINGS`, say — `lump/2` gives
  the last, and `level/2` gives a level's own lumps after its marker.
  """

  @enforce_keys [:kind, :lumps, :names]
  defstruct [:kind, :lumps, :names]

  @type lump :: {String.t(), binary()}
  @type t :: %__MODULE__{
          kind: :iwad | :pwad,
          lumps: tuple(),
          names: %{String.t() => non_neg_integer()}
        }

  @level_lumps ~w(THINGS LINEDEFS SIDEDEFS VERTEXES SEGS SSECTORS NODES SECTORS REJECT BLOCKMAP)

  @doc "Read the WAD at `path`."
  @spec open(Path.t()) :: {:ok, t()} | {:error, term()}
  def open(path) do
    with {:ok, bytes} <- File.read(path) do
      parse(bytes)
    end
  end

  @doc "Read a WAD from its bytes."
  @spec parse(binary()) :: {:ok, t()} | {:error, :not_a_wad | :truncated}
  def parse(<<magic::binary-size(4), count::little-32, offset::little-32, _rest::binary>> = bytes)
      when magic in ["IWAD", "PWAD"] do
    if byte_size(bytes) < offset + count * 16 do
      {:error, :truncated}
    else
      directory = binary_part(bytes, offset, count * 16)

      lumps =
        for <<at::little-32, size::little-32, name::binary-size(8) <- directory>> do
          {clean(name), binary_part(bytes, at, size)}
        end

      names =
        lumps |> Enum.with_index() |> Map.new(fn {{name, _data}, index} -> {name, index} end)

      {:ok, %__MODULE__{kind: kind(magic), lumps: List.to_tuple(lumps), names: names}}
    end
  end

  def parse(_bytes), do: {:error, :not_a_wad}

  defp kind("IWAD"), do: :iwad
  defp kind("PWAD"), do: :pwad

  defp clean(name), do: name |> String.split(<<0>>, parts: 2) |> hd() |> String.upcase()

  @doc "The last lump called `name`, or `nil`."
  @spec lump(t(), String.t()) :: binary() | nil
  def lump(%__MODULE__{} = wad, name) do
    case Map.get(wad.names, name) do
      nil -> nil
      index -> wad.lumps |> elem(index) |> elem(1)
    end
  end

  @doc "The last lump called `name`; raises `KeyError` where there is none."
  @spec lump!(t(), String.t()) :: binary()
  def lump!(wad, name), do: lump(wad, name) || raise(KeyError, key: name, term: :wad)

  @doc "Whether the WAD has a lump called `name`."
  @spec has?(t(), String.t()) :: boolean()
  def has?(%__MODULE__{names: names}, name), do: Map.has_key?(names, name)

  @doc """
  The lumps strictly between the markers `first` and `last`, in order. Markers that
  repeat with a doubled letter (`FF_START`, `PP_START`) are matched too.
  """
  @spec between(t(), String.t(), String.t()) :: [lump()]
  def between(%__MODULE__{lumps: lumps}, first, last) do
    lumps
    |> Tuple.to_list()
    |> Enum.reduce({false, []}, fn {name, data}, {inside?, acc} ->
      cond do
        marker?(name, first) -> {true, acc}
        marker?(name, last) -> {false, acc}
        inside? and data != <<>> -> {true, [{name, data} | acc]}
        true -> {inside?, acc}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp marker?(name, marker) do
    [prefix, suffix] = String.split(marker, "_", parts: 2)
    name == marker or name == String.duplicate(prefix, 2) <> "_" <> suffix
  end

  @doc "The names of the levels in the WAD, `E1M1` or `MAP01` style, in order."
  @spec levels(t()) :: [String.t()]
  def levels(%__MODULE__{lumps: lumps}) do
    list = Tuple.to_list(lumps)

    list
    |> Enum.with_index()
    |> Enum.filter(fn {{name, _data}, index} ->
      Regex.match?(~r/^(E\dM\d|MAP\d\d)$/, name) and
        match?({"THINGS", _data}, Enum.at(list, index + 1))
    end)
    |> Enum.map(fn {{name, _data}, _index} -> name end)
  end

  @doc "The lumps of level `name` by lump name: `THINGS`, `LINEDEFS` and the rest."
  @spec level(t(), String.t()) :: {:ok, %{String.t() => binary()}} | {:error, :no_such_level}
  def level(%__MODULE__{lumps: lumps, names: names}, name) do
    case Map.get(names, name) do
      nil ->
        {:error, :no_such_level}

      index ->
        found =
          (index + 1)..min(index + length(@level_lumps), tuple_size(lumps) - 1)
          |> Enum.map(&elem(lumps, &1))
          |> Enum.take_while(fn {lump_name, _data} -> lump_name in @level_lumps end)
          |> Map.new()

        {:ok, found}
    end
  end
end
