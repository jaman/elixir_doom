defmodule ElixirDoom.StatusBar do
  @moduledoc """
  Doom's status bar drawn onto a frame: ammunition, health, the weapons owned, the face,
  armour, keys and every ammunition count, laid out as Doom lays them out across the
  bottom 32 rows of its 320 by 200 screen and stretched to the frame.
  """

  alias Cauldron2D.Sectors.{Frame, Overlay}
  alias ElixirDoom.{Graphics, Tables}

  @slots [{2, :pistol}, {3, :shotgun}, {4, :chaingun}, {5, :missile}, {6, :plasma}, {7, :bfg}]
  @keys [
    {0, [:blue_card], [:blue_skull], 171},
    {1, [:yellow_card], [:yellow_skull], 181},
    {2, [:red_card], [:red_skull], 191}
  ]
  @ammo_rows [{:clip, 173}, {:shell, 179}, {:cell, 191}, {:misl, 185}]

  @doc "Draw the status bar for `view` onto `frame`, which is the bar's own size."
  @spec draw(Frame.t(), Graphics.t(), map()) :: Frame.t()
  def draw(frame, graphics, view) do
    player = view.player
    scale = {frame.width / 320, frame.height / 32}

    records =
      [
        patch(graphics, "STBAR", {0, 168}, scale),
        ready_ammo(graphics, player, scale),
        big(graphics, player.health, 90, scale),
        patch(graphics, "STTPRCNT", {90, 171}, scale),
        patch(graphics, "STARMS", {104, 168}, scale),
        arms(graphics, player, scale),
        patch(graphics, face(player, view.tic), {143, 168}, scale),
        big(graphics, player.armor, 221, scale),
        patch(graphics, "STTPRCNT", {221, 171}, scale),
        keys(graphics, player, scale),
        counts(graphics, player, scale)
      ]

    Frame.columns(Frame.fill(frame, 0), graphics.pictures, records)
  end

  defp patch(graphics, name, {x, y}, {sx, sy}) do
    case Graphics.patch(graphics, name) do
      nil ->
        []

      id ->
        info = Graphics.patch_info(graphics, name)

        rect =
          {(x - info.left) * sx, (y - 168 - info.top) * sy, info.width * sx, info.height * sy}

        Overlay.columns(graphics.pictures, id, rect, 0)
    end
  end

  defp ready_ammo(graphics, player, scale) do
    case Tables.weapon(player.ready).ammo do
      nil -> []
      kind -> big(graphics, Map.get(player.ammo, kind, 0), 44, scale)
    end
  end

  defp big(graphics, number, right, scale),
    do: digits(graphics, "STTNUM", number, {right, 171}, scale)

  defp digits(graphics, prefix, number, {right, y}, scale) do
    number = max(trunc(number), 0)
    text = Integer.to_string(number)

    {records, _x} =
      text
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.reduce({[], right}, fn digit, {acc, x} ->
        name = prefix <> digit
        width = (Graphics.patch_info(graphics, name) || %{width: 4}).width
        {[patch(graphics, name, {x - width, y}, scale) | acc], x - width}
      end)

    records
  end

  defp arms(graphics, player, scale) do
    for {{slot, weapon}, index} <- Enum.with_index(@slots) do
      owned? = MapSet.member?(player.weapons, weapon)
      prefix = if owned?, do: "STYSNUM", else: "STGNUM"

      patch(
        graphics,
        prefix <> Integer.to_string(slot),
        {111 + rem(index, 3) * 12, 172 + div(index, 3) * 10},
        scale
      )
    end
  end

  defp keys(graphics, player, scale) do
    for {index, cards, skulls, y} <- @keys,
        name = key_patch(player, index, cards, skulls),
        name != nil do
      patch(graphics, name, {239, y}, scale)
    end
  end

  defp key_patch(player, index, cards, skulls) do
    cond do
      Enum.any?(skulls, &MapSet.member?(player.cards, &1)) -> "STKEYS#{index + 3}"
      Enum.any?(cards, &MapSet.member?(player.cards, &1)) -> "STKEYS#{index}"
      true -> nil
    end
  end

  defp counts(graphics, player, scale) do
    for {kind, y} <- @ammo_rows do
      [
        digits(graphics, "STYSNUM", Map.get(player.ammo, kind, 0), {288, y}, scale),
        digits(graphics, "STYSNUM", Map.fetch!(player.max_ammo, kind), {314, y}, scale)
      ]
    end
  end

  defp face(%{status: :dead}, _tic), do: "STFDEAD0"

  defp face(player, tic) do
    pain = div((100 - min(max(player.health, 0), 100)) * 5, 101)

    cond do
      Map.get(player.powers, :invulnerability, 0) > 0 -> "STFGOD0"
      player.damage_count > 20 -> "STFOUCH#{pain}"
      player.damage_count > 0 -> "STFKILL#{pain}"
      true -> "STFST#{pain}#{rem(div(tic, 35), 3)}"
    end
  end
end
