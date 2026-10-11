defmodule ElixirDoom.Level do
  @moduledoc """
  A Doom level read from a WAD into a `Cauldron2D.Sectors.Map`, with the things placed in
  it.

      {:ok, level} = ElixirDoom.Level.load(wad, graphics, "E1M1")
      level.map
      level.things

  Wall and flat names are resolved to picture ids in `graphics`. The level keeps the BSP
  its WAD carries; `bsp: :build` builds one from the lines instead.

  A thing is `%{x:, y:, angle:, type:, flags:}`: the angle in radians and `flags` Doom's
  bits — `1` easy, `2` medium, `4` hard, `8` deaf, `16` multiplayer only.

  Line flags become the engine's names — `:blocks`, `:blocks_walkers`, `:upper_unpegged`,
  `:lower_unpegged`, `:secret`, `:blocks_sound`, `:hidden`, `:mapped` — and Doom's own
  numbered specials and tags are kept as they are.
  """

  alias Cauldron2D.Sectors.Map, as: SectorMap
  alias ElixirDoom.{Graphics, Wad}

  @enforce_keys [:name, :map, :things, :sky]
  defstruct [:name, :map, :things, :sky]

  @type thing :: %{x: float(), y: float(), angle: float(), type: integer(), flags: integer()}
  @type t :: %__MODULE__{name: String.t(), map: SectorMap.t(), things: [thing()], sky: String.t()}

  @line_flags [
    {1, :blocks},
    {2, :blocks_walkers},
    {8, :upper_unpegged},
    {16, :lower_unpegged},
    {32, :secret},
    {64, :blocks_sound},
    {128, :hidden},
    {256, :mapped}
  ]

  @doc ~s|Read level `name` (`"E1M1"`, `"MAP01"`) from `wad`.|
  @spec load(Wad.t(), Graphics.t(), String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def load(%Wad{} = wad, %Graphics{} = graphics, name, opts \\ []) do
    with {:ok, lumps} <- Wad.level(wad, name),
         :ok <- complete(lumps) do
      vertices = vertices(lumps["VERTEXES"])
      sides = sides(lumps["SIDEDEFS"], graphics)
      lines = lines(lumps["LINEDEFS"])

      map = %SectorMap{
        vertices: vertices,
        lines: lines,
        sides: sides,
        sectors: sectors(lumps["SECTORS"], graphics),
        blockmap: Map.get(lumps, "BLOCKMAP"),
        reject: Map.get(lumps, "REJECT")
      }

      map =
        if Keyword.get(opts, :bsp) == :build,
          do: SectorMap.with_bsp(map),
          else: wad_bsp(map, lumps)

      {:ok, %__MODULE__{name: name, map: map, things: things(lumps["THINGS"]), sky: sky(name)}}
    end
  end

  defp complete(lumps) do
    missing = Enum.reject(~w(THINGS LINEDEFS SIDEDEFS VERTEXES SECTORS), &Map.has_key?(lumps, &1))
    if missing == [], do: :ok, else: {:error, {:missing_lumps, missing}}
  end

  defp sky(<<"E", episode, "M", _rest::binary>>) when episode in ?1..?4, do: "SKY#{episode - ?0}"

  defp sky("MAP" <> number),
    do:
      if(String.to_integer(number) < 12,
        do: "SKY1",
        else: if(String.to_integer(number) < 21, do: "SKY2", else: "SKY3")
      )

  defp sky(_name), do: "SKY1"

  defp vertices(lump) do
    for(<<x::little-signed-16, y::little-signed-16 <- lump>>, do: {x * 1.0, y * 1.0})
    |> List.to_tuple()
  end

  defp lines(lump) do
    for <<from::little-16, to::little-16, flags::little-16, special::little-16, tag::little-16,
          front::little-16, back::little-16 <- lump>> do
      %{
        from: from,
        to: to,
        front: front,
        back: if(back == 0xFFFF, do: nil, else: back),
        flags: flag_set(flags),
        special: special,
        tag: tag
      }
    end
    |> List.to_tuple()
  end

  defp flag_set(flags) do
    for {bit, name} <- @line_flags, Bitwise.band(flags, bit) != 0, into: MapSet.new(), do: name
  end

  defp sides(lump, graphics) do
    for <<x_offset::little-signed-16, y_offset::little-signed-16, upper::binary-size(8),
          lower::binary-size(8), middle::binary-size(8), sector::little-16 <- lump>> do
      %{
        sector: sector,
        x_offset: x_offset * 1.0,
        y_offset: y_offset * 1.0,
        upper: texture(graphics, upper),
        lower: texture(graphics, lower),
        middle: texture(graphics, middle)
      }
    end
    |> List.to_tuple()
  end

  defp texture(graphics, name) do
    case clean(name) do
      "-" -> nil
      "" -> nil
      texture -> Graphics.wall(graphics, texture)
    end
  end

  defp sectors(lump, graphics) do
    for <<floor::little-signed-16, ceiling::little-signed-16, floor_flat::binary-size(8),
          ceiling_flat::binary-size(8), light::little-signed-16, special::little-signed-16,
          tag::little-signed-16 <- lump>> do
      %{
        floor: floor * 1.0,
        ceiling: ceiling * 1.0,
        floor_picture: Graphics.flat(graphics, clean(floor_flat)) || 0,
        ceiling_picture: Graphics.flat(graphics, clean(ceiling_flat)) || 0,
        floor_name: clean(floor_flat),
        ceiling_name: clean(ceiling_flat),
        light: light |> max(0) |> min(255),
        special: special,
        tag: tag
      }
    end
    |> List.to_tuple()
  end

  defp things(lump) do
    for <<x::little-signed-16, y::little-signed-16, angle::little-signed-16,
          type::little-signed-16, flags::little-signed-16 <- lump>> do
      %{x: x * 1.0, y: y * 1.0, angle: angle * :math.pi() / 180, type: type, flags: flags}
    end
  end

  defp wad_bsp(map, lumps) do
    segs =
      for <<from::little-16, to::little-16, _angle::little-signed-16, line::little-16,
            side::little-signed-16, offset::little-signed-16 <- lumps["SEGS"]>> do
        %{
          from: elem(map.vertices, from),
          to: elem(map.vertices, to),
          line: line,
          side: side,
          offset: offset * 1.0
        }
      end
      |> List.to_tuple()

    subsectors =
      for <<count::little-16, first::little-16 <- lumps["SSECTORS"]>> do
        seg = elem(segs, first)
        %{first: first, count: count, sector: SectorMap.side_sector(map, seg.line, seg.side)}
      end
      |> List.to_tuple()

    nodes =
      for <<x::little-signed-16, y::little-signed-16, dx::little-signed-16, dy::little-signed-16,
            rt::little-signed-16, rb::little-signed-16, rl::little-signed-16,
            rr::little-signed-16, lt::little-signed-16, lb::little-signed-16,
            ll::little-signed-16, lr::little-signed-16, right::little-16,
            left::little-16 <- lumps["NODES"]>> do
        %{
          x: x * 1.0,
          y: y * 1.0,
          dx: dx * 1.0,
          dy: dy * 1.0,
          boxes:
            {{rt * 1.0, rb * 1.0, rl * 1.0, rr * 1.0}, {lt * 1.0, lb * 1.0, ll * 1.0, lr * 1.0}},
          children: {child(right), child(left)}
        }
      end
      |> List.to_tuple()

    %{map | segs: segs, subsectors: subsectors, nodes: nodes}
  end

  defp child(value) do
    if Bitwise.band(value, 0x8000) != 0,
      do: {:leaf, Bitwise.band(value, 0x7FFF)},
      else: {:node, value}
  end

  defp clean(name), do: name |> String.split(<<0>>, parts: 2) |> hd() |> String.upcase()
end
