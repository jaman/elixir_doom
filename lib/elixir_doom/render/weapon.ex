defmodule ElixirDoom.Render.Weapon do
  @moduledoc """
  The weapon in the player's hands and its muzzle flash, drawn over the view as Doom
  draws its player sprites: placed on Doom's 320 by 168 view stretched to the view's
  size, lit by the player's sector, unlit when bright, through the fixed light table
  when one is in force, and as a shimmer while the player is partly invisible.

      frame = ElixirDoom.Render.Weapon.draw(frame, graphics, view, {width, height}, fixed)
      ElixirDoom.Render.Weapon.sprites(graphics, view, {width, height}, fixed)
  """

  alias Cauldron2D.Sectors.{Frame, Light, Overlay}
  alias ElixirDoom.{Graphics, Info}
  alias ElixirDoom.Render.Wash

  @shadow_table 6

  @type sprite :: %{
          picture: non_neg_integer(),
          rect: {float(), float(), float(), float()},
          light: non_neg_integer(),
          shimmer: boolean()
        }

  @doc "`frame` with the weapon drawn over it, the view being `width` by `height`."
  @spec draw(Frame.t(), Graphics.t(), map(), {pos_integer(), pos_integer()}, integer() | nil) ::
          Frame.t()
  def draw(frame, graphics, view, size, fixed) do
    records =
      for sprite <- sprites(graphics, view, size, fixed) do
        Overlay.columns(graphics.pictures, sprite.picture, sprite.rect, sprite.light,
          shimmer: sprite.shimmer
        )
      end

    Frame.columns(frame, graphics.pictures, records)
  end

  @doc """
  The weapon and flash pictures to draw for a view `width` by `height`: each its picture,
  the rectangle it fills in view pixels, its light table, and whether it shimmers.
  """
  @spec sprites(Graphics.t(), map(), {pos_integer(), pos_integer()}, integer() | nil) ::
          [sprite()]
  def sprites(graphics, view, {width, height}, fixed) do
    player = view.player
    scale_x = width / 320
    scale_y = height / 168
    sector_light = elem(view.sectors, view.me.sector).light
    base = max(Light.start(sector_light + player.extra_light * 16) - 23, 0)
    shadow? = Wash.showing?(Map.get(player.powers, :invisibility, 0))

    for slot <- [:weapon, :flash],
        sprite = Map.fetch!(player, slot),
        sprite.state != nil,
        state = Info.state(sprite.state),
        {name, frame_index, bright} = state.picture,
        {id, _flip, lump} <- List.wrap(Graphics.sprite(graphics, name, frame_index, 0)),
        info = Graphics.patch_info(graphics, lump) do
      shimmer = shadow? and not bright

      %{
        picture: id,
        rect:
          {(sprite.sx - info.left) * scale_x, (sprite.sy - info.top - 16) * scale_y,
           info.width * scale_x, info.height * scale_y},
        light: light(shimmer, fixed, bright, base),
        shimmer: shimmer
      }
    end
  end

  defp light(true, _fixed, _bright, _base), do: @shadow_table
  defp light(false, fixed, _bright, _base) when fixed != nil, do: fixed
  defp light(false, nil, true, _base), do: 0
  defp light(false, nil, false, base), do: base
end
