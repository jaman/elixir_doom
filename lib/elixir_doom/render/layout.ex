defmodule ElixirDoom.Render.Layout do
  @moduledoc """
  Where things go on a level's picture: the player's options with Doom's defaults filled
  in, the screen size in force (at least 10 while the automap is open), the status bar's
  height (32 of every 200 rows, none at size 11) and the height left above it for the view.

      %{bar_height: 64, view_height: 336} = ElixirDoom.Render.Layout.new({640, 400}, automap: false)
  """

  alias ElixirDoom.Menu

  @type t :: %{
          options: map(),
          automap: boolean(),
          blocks: integer(),
          bar_height: non_neg_integer(),
          view_height: pos_integer()
        }

  @doc "The layout of a picture `width` by `height` under `ElixirDoom.Render.picture/4`'s options."
  @spec new({pos_integer(), pos_integer()}, keyword()) :: t()
  def new({_width, height}, opts) do
    options = Map.merge(Menu.defaults(), Keyword.get(opts, :options, %{}))
    automap = Keyword.get(opts, :automap, false)
    blocks = if automap, do: max(options.screen_blocks, 10), else: options.screen_blocks
    bar_height = if blocks >= 11, do: 0, else: max(round(height * 32 / 200), 8)

    %{
      options: options,
      automap: automap,
      blocks: blocks,
      bar_height: bar_height,
      view_height: height - bar_height
    }
  end
end
