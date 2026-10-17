defmodule ElixirDoom.Gpu.Weapon do
  @moduledoc """
  The weapon of a partly invisible player for the graphics card: its shimmering
  pictures (`ElixirDoom.Render.Weapon.sprites/4`) as flat pictures held just in front of
  the camera, filling the same rectangles of the view as Doom draws them, drawn with
  `ElixirDoom.Gpu.Shimmer`. The weapon's other pictures are in the overlay.

      {changes, live, mesh} = ElixirDoom.Gpu.Weapon.changes(view, live, target, mesh, camera, look)

  `look` is `%{id:, window: {width, height}, fixed:}`: the instance id, the view's size
  in pixels and the fixed light table or `nil`. The camera's `fov_y` must show the
  view's width across a quarter turn.
  """

  alias CauldronGPU.{Camera, Handle, Instance, Mesh, Target, Transform}
  alias CauldronGPU.Sectors.Live
  alias ElixirDoom.Assets
  alias ElixirDoom.Gpu.Shimmer
  alias ElixirDoom.Render.Weapon

  @type look :: %{
          id: pos_integer(),
          window: {pos_integer(), pos_integer()},
          fixed: non_neg_integer() | nil
        }

  @doc "The changes that draw the shimmering weapon, with the live map and the mesh handle to keep."
  @spec changes(map(), Live.t(), Target.t(), Handle.t() | nil, Camera.t(), look()) ::
          {[CauldronGPU.Stream.change()], Live.t(), Handle.t() | nil}
  def changes(view, live, target, mesh, camera, look) do
    sprites =
      Assets.get().graphics
      |> Weapon.sprites(view, look.window, look.fixed)
      |> Enum.filter(& &1.shimmer)

    case sprites do
      [] ->
        {hidden(mesh, look.id), live, mesh}

      _ ->
        {built, pictures} = build(sprites, look.window, 2 * camera.near)

        {materials, live} =
          Enum.map_reduce(pictures, live, &Shimmer.material(&2, target, &1, look.fixed))

        {put, mesh} = put(built, mesh, target)
        {put ++ [instance(look.id, mesh, materials, camera)], live, mesh}
    end
  end

  defp hidden(nil, _id), do: []

  defp hidden(mesh, id),
    do: [{:instance, id, %Instance{mesh: mesh, hidden: true, shadows: false}}]

  defp put(built, nil, target), do: {[], Target.mesh(target, built)}
  defp put(built, mesh, _target), do: {[{:mesh, mesh.id, built}], mesh}

  defp instance(id, mesh, materials, camera) do
    {:instance, id,
     %Instance{
       mesh: mesh,
       materials: materials,
       shadows: false,
       in_front: true,
       snap: camera.snap,
       transform: %Transform{position: camera.position, rotation: camera.rotation}
     }}
  end

  defp build(sprites, {width, height}, distance) do
    quads =
      sprites
      |> Enum.with_index()
      |> Enum.map(fn {sprite, index} ->
        quad(sprite.rect, {width, height}, distance, index * 4)
      end)

    vertices = Enum.flat_map(quads, &elem(&1, 0))
    indices = Enum.flat_map(quads, &elem(&1, 1))
    parts = for index <- 0..(length(sprites) - 1), do: {index * 6, 6}
    {Mesh.new(vertices, indices, parts: parts), Enum.map(sprites, & &1.picture)}
  end

  defp quad({x, y, w, h}, {width, height}, distance, base) do
    corners = [
      {x, y + h, 0.0, 1.0},
      {x + w, y + h, 1.0, 1.0},
      {x + w, y, 1.0, 0.0},
      {x, y, 0.0, 0.0}
    ]

    vertices =
      for {px, py, u, v} <- corners do
        %{
          position:
            {(2 * px / width - 1) * distance, (1 - 2 * py / height) * height / width * distance,
             -distance},
          normal: {0.0, 0.0, 1.0},
          uv: {u, v}
        }
      end

    {vertices, Enum.map([0, 1, 2, 0, 2, 3], &(&1 + base))}
  end
end
