defmodule ElixirDoom.Gpu do
  @moduledoc """
  A player's view described for the graphics card, as a scene's `:gpu`
  (`Cauldron2D.Client.Game`): the same picture `ElixirDoom.Render` draws in software.

      {changes, cache} = ElixirDoom.Gpu.draw(view, opts, target, cache, {width, height}, aspect)

  The level is a `CauldronGPU.Sectors.Live` map, uploaded once per level and released
  when the level changes; its doors, lifts, lights, switches and animated pictures change
  as the view's sectors and sides do. Things are upright sprites
  (`ElixirDoom.Gpu.Sprites`); the weapon, status bar, messages, automap, menus and the
  screens between levels are the overlay (`ElixirDoom.Gpu.Overlay`), put again only when
  it changes, but for a partly invisible player's shimmering weapon
  (`ElixirDoom.Gpu.Weapon`); the palette washes are the screen tint
  (`ElixirDoom.Gpu.Tint`); the fixed light tables of invulnerability and light
  amplification draw every picture through that table at full light. Walls and flats
  are lit in display colour through the live map's light table, darkening with distance.

  The camera is the software view's: the eye's position and heading, drawn into the
  view's window above the status bar (smaller at Doom's smaller screen sizes), a
  quarter turn across the window's width, and a world unit drawn `1.2 * aspect` times
  taller than wide; at low detail the window shows half as many columns, each two
  pixels wide. The automap's seen lines are recorded as a 320 by 168 view sees them.

  `opts` are those of `ElixirDoom.Render.picture/4`.
  """

  alias CauldronGPU.{Camera, Environment, Target}
  alias CauldronGPU.Sectors
  alias CauldronGPU.Sectors.Live
  alias ElixirDoom.{Assets, Graphics, Render}
  alias ElixirDoom.Gpu.{Overlay, Sprites, Tint, Weapon}
  alias ElixirDoom.Render.{Border, Layout, Wash}

  @weapon_id 2
  @first_thing_id 1_000_000
  @first_sector_id 3
  @snap_distance 64.0
  @seen_size {320, 168}

  @type cache :: %{
          level: String.t() | nil,
          live: Live.t() | nil,
          sprites: Sprites.t() | nil,
          weapon: CauldronGPU.Handle.t() | nil,
          surroundings: {term(), term()} | nil,
          overlay: CauldronGPU.Handle.t() | nil,
          overlay_rgba: binary() | nil,
          tint: tuple() | nil,
          eye: {number(), number(), number()} | nil
        }

  @doc "The tick's changes for `view` drawn at `size` with pixels `aspect` wide, and the cache for next time."
  @spec draw(
          map(),
          keyword(),
          Target.t(),
          cache() | nil,
          {pos_integer(), pos_integer()},
          number()
        ) ::
          {[CauldronGPU.Stream.change()], cache()}
  def draw(view, opts, target, cache, size, aspect) do
    {opening, cache} = opening(cache)
    {world, cache} = world(view, opts, target, cache, size, aspect)
    {overlay, cache} = overlay(view, opts, target, cache)
    {tint, cache} = tint(view, cache)
    {opening ++ world ++ overlay ++ tint, cache}
  end

  defp opening(nil) do
    {[environment({nil, nil}), {:effects, []}],
     %{
       level: nil,
       live: nil,
       sprites: nil,
       weapon: nil,
       surroundings: nil,
       overlay: nil,
       overlay_rgba: nil,
       tint: nil,
       eye: nil
     }}
  end

  defp opening(cache), do: {[], cache}

  defp environment({light_table, sky}) do
    %Environment{
      sky_top: {0.0, 0.0, 0.0},
      sky_horizon: {0.0, 0.0, 0.0},
      sky_ground: {0.0, 0.0, 0.0},
      ambient_intensity: 0.0,
      fog_density: 0.0,
      reflections: 0.0,
      ao_strength: 0.0,
      bloom_strength: 0.0,
      exposure: 1.0,
      tone_map: :clamp,
      light_space: :display,
      light_table: light_table,
      sky_picture: sky && {:box, sky}
    }
  end

  defp world(%{phase: :level, me: %{}} = view, opts, target, cache, size, aspect) do
    {closing, cache} = level(cache, target, view.level)
    stretch = 1.2 * aspect
    fixed = Wash.fixed_table(view.player)
    extra = view.player.extra_light * 16
    {sectors, sides, shown} = unanimated(view)

    {map_changes, live} =
      Live.update(cache.live, target, sectors, sides,
        shown: shown,
        extra_light: extra,
        fixed: fixed,
        stretch: stretch
      )

    {camera, window} = camera(view, live, {size, opts}, stretch, cache.eye)
    look = %{first_id: @first_thing_id, stretch: stretch, fixed: fixed, extra_light: extra}

    {sprite_changes, live, sprites} =
      Sprites.changes(view, live, target, cache.sprites, camera, look)

    {weapon_changes, live, weapon} =
      Weapon.changes(view, live, target, cache.weapon, camera, %{
        id: @weapon_id,
        window: window,
        fixed: fixed
      })

    Render.record_seen(view, Keyword.get(opts, :seen_key), @seen_size, aspect)
    {sky, live} = Live.sky_box(live, target, stretch, fixed)
    {lighting, surroundings} = lighting({Live.light_table(live), sky}, cache.surroundings)

    {closing ++ lighting ++ map_changes ++ sprite_changes ++ weapon_changes ++ [camera],
     %{
       cache
       | live: live,
         sprites: sprites,
         weapon: weapon,
         surroundings: surroundings,
         eye: {view.eye.x, view.eye.y, view.eye.z}
     }}
  end

  defp world(_view, _opts, _target, cache, _size, _aspect), do: {[], cache}

  defp lighting(same, same), do: {[], same}
  defp lighting(surroundings, _sent), do: {[environment(surroundings)], surroundings}

  defp level(%{level: name} = cache, _target, name), do: {[], cache}

  defp level(cache, target, name) do
    closing = if cache.live, do: Live.close(cache.live, target), else: []
    {:ok, level} = Assets.level(name)
    graphics = Assets.get().graphics

    live =
      Live.new(level.map, graphics.elixir_pictures, Graphics.palette(graphics, 0),
        sky: Graphics.wall(graphics, level.sky),
        sky_flats: Enum.reject([Graphics.flat(graphics, "F_SKY1")], &is_nil/1),
        first_id: @first_sector_id
      )

    {closing, %{cache | level: name, live: live, eye: nil}}
  end

  defp unanimated(view) do
    shown = Assets.animation_frame(Assets.get(), view.tic)
    base = Map.new(shown, fn {picture, showing} -> {showing, picture} end)
    {base_sectors(view.sectors, base), base_sides(view.sides, base), shown}
  end

  defp base_sectors(sectors, base) when map_size(base) == 0, do: sectors

  defp base_sectors(sectors, base) do
    sectors
    |> Tuple.to_list()
    |> Enum.map(fn sector ->
      %{
        sector
        | floor_picture: Map.get(base, sector.floor_picture, sector.floor_picture),
          ceiling_picture: Map.get(base, sector.ceiling_picture, sector.ceiling_picture)
      }
    end)
    |> List.to_tuple()
  end

  defp base_sides(sides, base) when map_size(base) == 0, do: sides

  defp base_sides(sides, base) do
    sides
    |> Tuple.to_list()
    |> Enum.map(fn side ->
      %{
        side
        | upper: Map.get(base, side.upper, side.upper),
          middle: Map.get(base, side.middle, side.middle),
          lower: Map.get(base, side.lower, side.lower)
      }
    end)
    |> List.to_tuple()
  end

  defp camera(view, live, {{width, height} = size, opts}, stretch, last_eye) do
    eye = {view.eye.x, view.eye.y, view.eye.z}
    layout = Layout.new(size, opts)

    {left, top, inner_width, inner_height} =
      Border.window(layout.blocks, {width, layout.view_height})

    camera = %Camera{
      position: Live.point(live, eye, stretch),
      rotation: Sectors.facing(view.eye.angle * 180 / :math.pi()),
      fov_y: 2 * :math.atan(inner_height / inner_width),
      near: live.scale,
      far: Live.far(live, stretch),
      snap: jumped?(last_eye, eye),
      viewport: {left / width, top / height, inner_width / width, inner_height / height},
      resolution: resolution(layout.options.detail, inner_width, inner_height)
    }

    {camera, {inner_width, inner_height}}
  end

  defp resolution(:low, width, height), do: {max(div(width, 2), 1), height}
  defp resolution(_detail, _width, _height), do: nil

  defp jumped?(nil, _eye), do: true

  defp jumped?({x, y, z}, {nx, ny, nz}),
    do: :math.sqrt((nx - x) ** 2 + (ny - y) ** 2 + (nz - z) ** 2) > @snap_distance

  defp overlay(view, opts, target, cache) do
    rgba = Overlay.rgba(view, opts)

    cond do
      rgba == cache.overlay_rgba ->
        {[], cache}

      cache.overlay == nil ->
        handle = Target.texture(target, overlay_texture(rgba))
        {[{:overlay, handle}], %{cache | overlay: handle, overlay_rgba: rgba}}

      true ->
        {[{:texture, cache.overlay.id, overlay_texture(rgba)}, {:overlay, cache.overlay}],
         %{cache | overlay_rgba: rgba}}
    end
  end

  defp overlay_texture(rgba) do
    {width, height} = Overlay.size()

    %CauldronGPU.Texture{
      width: width,
      height: height,
      pixels: rgba,
      filter: :nearest,
      wrap: :clamp,
      mipmaps: false
    }
  end

  defp tint(%{phase: :level, me: %{}} = view, cache),
    do: tinted(Tint.of(Assets.get().graphics, Wash.palette_index(view.player)), cache)

  defp tint(_view, cache), do: tinted({0.0, 0.0, 0.0, 0.0}, cache)

  defp tinted(tint, %{tint: tint} = cache), do: {[], cache}
  defp tinted(tint, cache), do: {[{:screen_tint, tint}], %{cache | tint: tint}}
end
