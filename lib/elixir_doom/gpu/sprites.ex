defmodule ElixirDoom.Gpu.Sprites do
  @moduledoc """
  The things of a level view as upright pictures for the graphics card, one instance a
  thing, kept under the thing's id so the renderer moves it smoothly between ticks.

      {changes, live, sprites} = ElixirDoom.Gpu.Sprites.changes(view, live, target, sprites, camera, look)

  Each thing stands on its feet with its picture's offsets, mirrored where the view says,
  turned to face the view as Doom's sprites do, its see-through texels cut out. It
  stands in its sector (`CauldronGPU.Instance`'s `standing`): its sector's own floor and
  ceiling heights do not hide it, so it shows whole where it sinks into them, while walls
  and the raised floors and lowered ceilings of other sectors in front of it do; things
  are drawn farthest first. It is lit as the software view lights it: by its sector's
  light (plus the view's extra light) at its distance from the eye, fully when bright,
  through the fixed light table when one is in force. A shimmering thing is drawn as
  `ElixirDoom.Gpu.Shimmer` draws it.

  `sprites` is what the last call returned (`nil` the first time): each picture's quad
  mesh and the ids placed. `look` is `%{first_id:, stretch:, fixed:, extra_light:}`: the
  instance id of a thing with id `0` (a thing's instance is that plus its id), how many
  times taller than wide a unit is drawn, the fixed light table or `nil`, and the light
  added.
  """

  alias Cauldron2D.Sectors.Pictures
  alias CauldronGPU.{Camera, Handle, Instance, Material, Mesh, Target, Transform}
  alias CauldronGPU.Sectors.{Light, Live}
  alias ElixirDoom.Assets
  alias ElixirDoom.Gpu.Shimmer

  @nearest 4.0

  @type look :: %{
          first_id: pos_integer(),
          stretch: number(),
          fixed: non_neg_integer() | nil,
          extra_light: integer()
        }
  @type t :: %{meshes: %{{non_neg_integer(), boolean()} => Handle.t()}, placed: MapSet.t()}

  @doc "The changes that draw `view`'s things, with the live map and the sprites to keep."
  @spec changes(map(), Live.t(), Target.t(), t() | nil, Camera.t(), look()) ::
          {[CauldronGPU.Stream.change()], Live.t(), t()}
  def changes(view, live, target, nil, camera, look),
    do: changes(view, live, target, %{meshes: %{}, placed: MapSet.new()}, camera, look)

  def changes(view, live, target, sprites, camera, look) do
    pictures = Assets.get().graphics.pictures

    {placing, {live, meshes}} =
      view.things
      |> Enum.filter(&(depth(&1, view) >= @nearest))
      |> Enum.map_reduce({live, sprites.meshes}, fn thing, {live, meshes} ->
        place(thing, {view, camera, look}, {live, meshes}, {target, pictures})
      end)

    placed = MapSet.new(placing, &elem(&1, 1))

    removed =
      for id <- MapSet.difference(sprites.placed, placed), do: {:remove_instance, id}

    changes =
      Enum.map(placing, fn {:instance, id, instance} ->
        {:instance, id, %{instance | snap: not MapSet.member?(sprites.placed, id)}}
      end)

    {removed ++ changes, live, %{meshes: meshes, placed: placed}}
  end

  defp depth(thing, view) do
    (thing.x - view.eye.x) * :math.cos(view.eye.angle) +
      (thing.y - view.eye.y) * :math.sin(view.eye.angle)
  end

  defp place(thing, {view, camera, look}, {live, meshes}, {target, pictures}) do
    flip = Map.get(thing, :flip, false)
    {mesh, meshes} = mesh(meshes, target, pictures, thing, flip)
    {material, live} = material(key(thing, view, depth(thing, view), look), live, target)

    sector = elem(view.sectors, thing.sector)

    instance = %Instance{
      mesh: mesh,
      materials: [material],
      shadows: false,
      standing: {height(live, sector.floor, look), height(live, sector.ceiling, look)},
      transform: %Transform{
        position: Live.point(live, {thing.x, thing.y, thing.z}, look.stretch),
        rotation: camera.rotation,
        scale: {live.scale, live.scale * look.stretch, live.scale}
      }
    }

    {{:instance, look.first_id + thing.id, instance}, {live, meshes}}
  end

  defp height(live, z, look), do: elem(Live.point(live, {0.0, 0.0, z}, look.stretch), 1)

  defp mesh(meshes, target, pictures, thing, flip) do
    key = {thing.picture, flip}

    case Map.fetch(meshes, key) do
      {:ok, handle} ->
        {handle, meshes}

      :error ->
        handle =
          Target.mesh(
            target,
            quad(Pictures.size(pictures, thing.picture), Map.get(thing, :offset, {0, 0}), flip)
          )

        {handle, Map.put(meshes, key, handle)}
    end
  end

  defp quad({width, height}, {left, top}, flip) do
    {u0, u1} = if flip, do: {1.0, 0.0}, else: {0.0, 1.0}
    {x0, x1} = {-left * 1.0, (width - left) * 1.0}
    {y0, y1} = {(top - height) * 1.0, top * 1.0}

    vertices =
      for {x, y, u, v} <- [
            {x0, y0, u0, 1.0},
            {x1, y0, u1, 1.0},
            {x1, y1, u1, 0.0},
            {x0, y1, u0, 0.0}
          ],
          do: %{position: {x, y, 0.0}, normal: {0.0, 0.0, 1.0}, uv: {u, v}}

    Mesh.new(vertices, [0, 1, 2, 0, 2, 3])
  end

  defp key(%{shimmer: true} = thing, _view, _depth, look),
    do: {:shimmer, thing.picture, look.fixed}

  defp key(thing, _view, _depth, %{fixed: fixed}) when fixed != nil,
    do: {:sprite, thing.picture, fixed, 1.0}

  defp key(%{bright: true} = thing, _view, _depth, _look), do: {:sprite, thing.picture, nil, 1.0}

  defp key(thing, view, depth, look) do
    level = elem(view.sectors, thing.sector).light + look.extra_light
    {:sprite, thing.picture, nil, Light.brightness(level, depth)}
  end

  defp material({:shimmer, picture, table}, live, target),
    do: Shimmer.material(live, target, picture, table)

  defp material({:sprite, _picture, _table, brightness} = key, live, target) do
    Live.material(live, target, key, fn texture ->
      %Material{
        base_texture: texture.handle,
        base_color: {brightness, brightness, brightness, 1.0},
        unlit: true,
        alpha_cutoff: 0.5,
        double_sided: true
      }
    end)
  end
end
