defmodule ElixirDoom.Actions do
  @moduledoc """
  The actions things run on entering a state, by the names the state table gives them.

      ElixirDoom.Actions.run(world, id, :a_chase)

  Actions of Doom II's monsters that the WAD being played has no use for, and the weapon
  actions (run by `ElixirDoom.Weapons` on a player's weapon, not on a thing), do nothing
  here.
  """

  alias ElixirDoom.{Combat, Enemy, Player, World}

  @doc "Run `action` for thing `id`."
  @spec run(World.t(), term(), atom()) :: World.t()
  def run(world, id, :a_look), do: Enemy.look(world, id)
  def run(world, id, :a_chase), do: Enemy.chase(world, id)
  def run(world, id, :a_facetarget), do: Enemy.face_target(world, id)
  def run(world, id, :a_posattack), do: Enemy.pistol(world, id)
  def run(world, id, :a_sposattack), do: Enemy.shotgun(world, id)
  def run(world, id, :a_cposattack), do: Enemy.chaingun(world, id)
  def run(world, id, :a_troopattack), do: Enemy.imp(world, id)
  def run(world, id, :a_sargattack), do: Enemy.bite(world, id)
  def run(world, id, :a_headattack), do: Enemy.caco(world, id)
  def run(world, id, :a_bruisattack), do: Enemy.baron(world, id)
  def run(world, id, :a_skullattack), do: Enemy.charge(world, id)
  def run(world, id, :a_pain), do: Enemy.pain(world, id)
  def run(world, id, :a_scream), do: Enemy.scream(world, id)
  def run(world, id, :a_xscream), do: Enemy.slop(world, id)
  def run(world, id, :a_fall), do: Enemy.fall(world, id)
  def run(world, id, :a_explode), do: Enemy.explode(world, id)
  def run(world, id, :a_bossdeath), do: Enemy.boss_death(world, id)
  def run(world, id, :a_playerscream), do: Player.scream(world, id)
  def run(world, id, :a_cyberattack), do: Enemy.rocket(world, id)
  def run(world, id, :a_hoof), do: Enemy.stomp(world, id, "DSHOOF")
  def run(world, id, :a_metal), do: Enemy.stomp(world, id, "DSMETAL")
  def run(world, id, :a_spidrefire), do: Enemy.refire(world, id, 10)
  def run(world, id, :a_cposrefire), do: Enemy.refire(world, id, 40)
  def run(world, id, :a_bfgspray), do: Combat.bfg_spray(world, id)
  def run(world, _id, _action), do: world
end
