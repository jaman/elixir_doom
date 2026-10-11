defmodule ElixirDoom.Graphics do
  @moduledoc """
  Doom's pictures read out of a WAD into one `Cauldron2D.Sectors.Pictures` set: the
  composed wall textures, the floor flats, every patch — sprites, the status bar, the
  weapons — and the palettes and light tables to draw them with.

      graphics = ElixirDoom.Graphics.load(wad)
      ElixirDoom.Graphics.wall(graphics, "STARTAN3")
      ElixirDoom.Graphics.sprite(graphics, "TROO", 0, 3)

  Pictures are named `{:wall, name}`, `{:flat, name}` and `{:patch, name}` in the set.
  `palettes` holds the WAD's fourteen 768-byte palettes in order: `0` normal, `1..8`
  hurt, `9..12` picking up, `13` the radiation suit.
  """

  alias Cauldron2D.Sectors.Pictures
  alias ElixirDoom.Wad

  @enforce_keys [:pictures, :palettes, :sprites, :patches]
  defstruct [:pictures, :palettes, :sprites, :patches, :textures, :flats]

  @type t :: %__MODULE__{
          pictures: Pictures.t(),
          palettes: tuple(),
          sprites: %{String.t() => %{non_neg_integer() => tuple()}},
          patches: %{
            String.t() => %{
              left: integer(),
              top: integer(),
              width: pos_integer(),
              height: pos_integer()
            }
          },
          textures: [String.t()],
          flats: [String.t()]
        }

  @doc "Read every picture in `wad`. `native: false` keeps the pictures in Elixir."
  @spec load(Wad.t(), keyword()) :: t()
  def load(%Wad{} = wad, opts \\ []) do
    patch_lumps = all_patches(wad)
    decoded = Map.new(patch_lumps, fn {name, data} -> {name, decode_patch(data)} end)
    textures = textures(wad, decoded)

    flats =
      for {name, data} <- Wad.between(wad, "F_START", "F_END"),
          byte_size(data) == 4096,
          do: {name, data}

    named =
      Enum.map(textures, fn {name, picture} -> {{:wall, name}, picture} end) ++
        Enum.map(flats, fn {name, data} -> {{:flat, name}, Pictures.from_rows(64, 64, data)} end) ++
        Enum.map(decoded, fn {name, patch} ->
          {{:patch, name}, Map.take(patch, [:width, :height, :pixels, :mask])}
        end)

    pictures = Pictures.new(named, Wad.lump!(wad, "COLORMAP"), opts)

    %__MODULE__{
      pictures: pictures,
      palettes: wad |> Wad.lump!("PLAYPAL") |> chunks(768) |> List.to_tuple(),
      sprites: sprites(wad, pictures),
      patches:
        Map.new(decoded, fn {name, patch} ->
          {name, Map.take(patch, [:left, :top, :width, :height])}
        end),
      textures: Enum.map(textures, &elem(&1, 0)),
      flats: Enum.map(flats, &elem(&1, 0))
    }
  end

  @doc "The picture id of wall texture `name`, or `nil` for `\"-\"` or an unknown name."
  @spec wall(t(), String.t()) :: non_neg_integer() | nil
  def wall(%__MODULE__{pictures: pictures}, name),
    do: Pictures.id(pictures, {:wall, String.upcase(name)})

  @doc "The picture id of flat `name`, or `nil`."
  @spec flat(t(), String.t()) :: non_neg_integer() | nil
  def flat(%__MODULE__{pictures: pictures}, name),
    do: Pictures.id(pictures, {:flat, String.upcase(name)})

  @doc "The picture id of patch `name`, or `nil`."
  @spec patch(t(), String.t()) :: non_neg_integer() | nil
  def patch(%__MODULE__{pictures: pictures}, name),
    do: Pictures.id(pictures, {:patch, String.upcase(name)})

  @doc "A patch's `%{left:, top:, width:, height:}`."
  @spec patch_info(t(), String.t()) :: map() | nil
  def patch_info(%__MODULE__{patches: patches}, name), do: Map.get(patches, name)

  @doc """
  The picture of sprite `name` at `frame` (`0` for `A`) seen from `rotation` (`0` for
  the front, counting round anticlockwise in eighths): `{picture_id, flip?, lump}`, or
  `nil` where the WAD lacks it.
  """
  @spec sprite(t(), String.t(), non_neg_integer(), 0..7) ::
          {non_neg_integer(), boolean(), String.t()} | nil
  def sprite(%__MODULE__{sprites: sprites}, name, frame, rotation) do
    with %{} = frames <- Map.get(sprites, name),
         rotations when is_tuple(rotations) <- Map.get(frames, frame) do
      elem(rotations, rotation)
    else
      _missing -> nil
    end
  end

  @doc "Palette `index` of the fourteen."
  @spec palette(t(), 0..13) :: binary()
  def palette(%__MODULE__{palettes: palettes}, index), do: elem(palettes, index)

  defp all_patches(wad) do
    names = wad |> pnames() |> MapSet.new()

    sprite_lumps = Wad.between(wad, "S_START", "S_END")
    patch_lumps = Wad.between(wad, "P_START", "P_END")

    graphics =
      for {name, data} <- Tuple.to_list(wad.lumps),
          graphic?(name, names),
          valid_patch?(data),
          do: {name, data}

    (patch_lumps ++ sprite_lumps ++ graphics)
    |> Enum.filter(fn {_name, data} -> valid_patch?(data) end)
    |> Map.new()
    |> Map.to_list()
  end

  defp graphic?(name, names) do
    MapSet.member?(names, name) or
      Enum.any?(
        ~w(ST WI M_ HU BRDR TITLEPIC INTERPIC HELP CREDIT VICTORY PFUB END STF STB STC STG STK STY STP STR WIA),
        &String.starts_with?(name, &1)
      )
  end

  defp valid_patch?(
         <<width::little-16, height::little-16, _left::little-signed-16, _top::little-signed-16,
           rest::binary>> = data
       )
       when width > 0 and height > 0 and width < 2048 and height < 2048 do
    byte_size(rest) >= width * 4 and
      Enum.all?(0..(width - 1), fn column ->
        <<offset::little-32>> = binary_part(rest, column * 4, 4)
        offset < byte_size(data)
      end)
  end

  defp valid_patch?(_data), do: false

  @doc false
  def decode_patch(
        <<width::little-16, height::little-16, left::little-signed-16, top::little-signed-16,
          rest::binary>> =
          data
      ) do
    offsets = for <<offset::little-32 <- binary_part(rest, 0, width * 4)>>, do: offset

    {pixels, mask} =
      offsets
      |> Enum.map(&column(data, &1, height))
      |> Enum.unzip()

    %{
      width: width,
      height: height,
      left: left,
      top: top,
      pixels: IO.iodata_to_binary(pixels),
      mask: IO.iodata_to_binary(mask)
    }
  end

  defp column(data, offset, height) do
    posts = posts(data, offset, -1, [])
    pixels = :array.new(height, default: 0)
    mask = :array.new(height, default: 0)

    {pixels, mask} = Enum.reduce(posts, {pixels, mask}, &place_post(&1, &2, height))

    {:binary.list_to_bin(:array.to_list(pixels)), :binary.list_to_bin(:array.to_list(mask))}
  end

  defp place_post({top, bytes}, columns, height) do
    bytes
    |> :binary.bin_to_list()
    |> Enum.with_index(top)
    |> Enum.filter(fn {_byte, row} -> row >= 0 and row < height end)
    |> Enum.reduce(columns, fn {byte, row}, {pixels, mask} ->
      {:array.set(row, byte, pixels), :array.set(row, 1, mask)}
    end)
  end

  defp posts(data, offset, previous, acc) when offset < byte_size(data) do
    case binary_part(data, offset, byte_size(data) - offset) do
      <<255, _rest::binary>> ->
        Enum.reverse(acc)

      <<delta, length, _pad, rest::binary>> when byte_size(rest) >= length ->
        top = if delta <= previous, do: previous + delta, else: delta
        posts(data, offset + 4 + length, top, [{top, binary_part(rest, 0, length)} | acc])

      _truncated ->
        Enum.reverse(acc)
    end
  end

  defp posts(_data, _offset, _previous, acc), do: Enum.reverse(acc)

  defp pnames(wad) do
    case Wad.lump(wad, "PNAMES") do
      <<count::little-32, rest::binary>> ->
        for <<name::binary-size(8) <- binary_part(rest, 0, count * 8)>>, do: clean(name)

      nil ->
        []
    end
  end

  defp clean(name), do: name |> String.split(<<0>>, parts: 2) |> hd() |> String.upcase()

  defp textures(wad, decoded) do
    patch_names = wad |> pnames() |> List.to_tuple()

    ["TEXTURE1", "TEXTURE2"]
    |> Enum.map(&Wad.lump(wad, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(&texture_definitions/1)
    |> Enum.map(fn definition -> {definition.name, compose(definition, patch_names, decoded)} end)
  end

  defp texture_definitions(<<count::little-32, rest::binary>> = lump) do
    offsets = for <<offset::little-32 <- binary_part(rest, 0, count * 4)>>, do: offset

    Enum.map(offsets, fn offset ->
      <<name::binary-size(8), _masked::little-32, width::little-16, height::little-16,
        _directory::little-32, patch_count::little-16, patches::binary>> =
        binary_part(lump, offset, byte_size(lump) - offset)

      placed =
        for <<x::little-signed-16, y::little-signed-16, patch::little-16, _step::little-16,
              _colormap::little-16 <-
                binary_part(patches, 0, patch_count * 10)>>,
            do: {x, y, patch}

      %{name: clean(name), width: width, height: height, patches: placed}
    end)
  end

  defp compose(definition, patch_names, decoded) do
    %{width: width, height: height} = definition
    canvas = :array.new(width * height, default: 0)
    mask = :array.new(width * height, default: 0)

    {canvas, mask} =
      Enum.reduce(definition.patches, {canvas, mask}, fn {x0, y0, index}, acc ->
        name = if index < tuple_size(patch_names), do: elem(patch_names, index)

        case Map.get(decoded, name) do
          nil -> acc
          patch -> blit(acc, patch, {x0, y0}, {width, height})
        end
      end)

    mask_binary = :binary.list_to_bin(:array.to_list(mask))
    holes? = :binary.match(mask_binary, <<0>>) != :nomatch

    %{
      width: width,
      height: height,
      pixels: :binary.list_to_bin(:array.to_list(canvas)),
      mask: if(holes?, do: mask_binary)
    }
  end

  defp blit({canvas, mask}, patch, {x0, y0}, {width, height}) do
    for px <- 0..(patch.width - 1),
        x = x0 + px,
        x >= 0 and x < width,
        py <- 0..(patch.height - 1),
        y = y0 + py,
        y >= 0 and y < height,
        :binary.at(patch.mask, px * patch.height + py) == 1,
        reduce: {canvas, mask} do
      {c, m} ->
        index = x * height + y

        {:array.set(index, :binary.at(patch.pixels, px * patch.height + py), c),
         :array.set(index, 1, m)}
    end
  end

  defp sprites(wad, pictures) do
    wad
    |> Wad.between("S_START", "S_END")
    |> Enum.reduce(%{}, fn {lump, _data}, acc ->
      id = Pictures.id(pictures, {:patch, lump})
      if id, do: add_sprite(acc, lump, id), else: acc
    end)
    |> Map.new(fn {name, frames} ->
      {name, Map.new(frames, fn {frame, rotations} -> {frame, rotations_tuple(rotations)} end)}
    end)
  end

  defp add_sprite(acc, <<name::binary-size(4), frame, rotation, rest::binary>> = lump, id) do
    acc = put_rotation(acc, name, frame - ?A, rotation - ?0, {id, false, lump})

    case rest do
      <<frame2, rotation2>> ->
        put_rotation(acc, name, frame2 - ?A, rotation2 - ?0, {id, true, lump})

      _single ->
        acc
    end
  end

  defp add_sprite(acc, _lump, _id), do: acc

  defp put_rotation(acc, name, frame, rotation, entry) do
    Map.update(acc, name, %{frame => %{rotation => entry}}, fn frames ->
      Map.update(frames, frame, %{rotation => entry}, &Map.put(&1, rotation, entry))
    end)
  end

  defp rotations_tuple(%{0 => entry}), do: List.to_tuple(List.duplicate(entry, 8))

  defp rotations_tuple(rotations) do
    1..8
    |> Enum.map(&Map.get(rotations, &1, rotations |> Map.values() |> hd()))
    |> List.to_tuple()
  end

  defp chunks(binary, size), do: for(<<chunk::binary-size(^size) <- binary>>, do: chunk)
end
