defmodule ElixirDoom.Render.Wash do
  @moduledoc """
  How a player's state colours the whole picture: the palette it is drawn through (red
  when hurt or berserk, gold on a pickup, green in a radiation suit) and the light table
  that replaces lighting while invulnerable or wearing light amplification goggles.

      ElixirDoom.Render.Wash.palette_index(player)
      ElixirDoom.Render.Wash.fixed_table(player)
  """

  @doc "Which of the fourteen palettes `player`'s screen is drawn through, `0` normal."
  @spec palette_index(map()) :: 0..13
  def palette_index(player) do
    strength = Map.get(player.powers, :strength, 0)
    berserk = if strength > 0, do: 12 - div(strength, 64), else: 0
    count = max(player.damage_count, berserk)

    cond do
      count > 0 -> min(div(count + 7, 8), 7) + 1
      player.bonus_count > 0 -> min(div(player.bonus_count + 7, 8), 3) + 9
      showing?(Map.get(player.powers, :ironfeet, 0)) -> 13
      true -> 0
    end
  end

  @doc "The light table everything is drawn through for `player`, or `nil` to light it as usual."
  @spec fixed_table(map()) :: non_neg_integer() | nil
  def fixed_table(player) do
    cond do
      showing?(Map.get(player.powers, :invulnerability, 0)) -> 32
      showing?(Map.get(player.powers, :infrared, 0)) -> 1
      true -> nil
    end
  end

  @doc "Whether a power with `tics` left shows: steadily, then blinking for its last four seconds."
  @spec showing?(integer()) :: boolean()
  def showing?(tics), do: tics > 4 * 32 or (Bitwise.band(tics, 8) != 0 and tics > 0)
end
