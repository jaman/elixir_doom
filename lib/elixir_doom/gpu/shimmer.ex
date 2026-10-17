defmodule ElixirDoom.Gpu.Shimmer do
  @moduledoc """
  Doom's shimmer (a spectre, a partly invisible player's weapon) as a graphics card
  material: the picture's shape filled with what is behind it, each row taken from one
  of Doom's 200 screen rows above or below, darkened as light table 6 darkens.

      {material, live} = ElixirDoom.Gpu.Shimmer.material(live, target, picture, table)

  `table` is the fixed light table in force, or `nil`; it keys the material with the
  picture's texture through that table, whose alpha cuts the shape.
  """

  alias CauldronGPU.{Handle, Material, Target}
  alias CauldronGPU.Sectors.Live

  @rows 200
  @maps 32
  @shadow_table 6

  @doc "The shimmer material of `picture`, made the first time."
  @spec material(Live.t(), Target.t(), non_neg_integer(), non_neg_integer() | nil) ::
          {Handle.t(), Live.t()}
  def material(live, target, picture, table) do
    darkening = :math.pow((@maps - @shadow_table) / @maps, 2.2)

    Live.material(live, target, {:shimmer, picture, table}, fn texture ->
      %Material{
        base_texture: texture.handle,
        base_color: {darkening, darkening, darkening, 1.0},
        alpha_cutoff: 0.5,
        smear: 1 / @rows,
        unlit: true,
        double_sided: true
      }
    end)
  end
end
