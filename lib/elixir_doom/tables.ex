defmodule ElixirDoom.Tables do
  @moduledoc """
  Doom's fixed tables: the random table every chance is drawn from, the weapons and their
  states, ammunition, the textures and flats that animate, and the switch pairs.

      ElixirDoom.Tables.random(0)
      ElixirDoom.Tables.weapon(:shotgun)
      ElixirDoom.Tables.switch("SW1BRCOM")
  """

  @random {0, 8, 109, 220, 222, 241, 149, 107, 75, 248, 254, 140, 16, 66, 74, 21, 211, 47, 80,
           242, 154, 27, 205, 128, 161, 89, 77, 36, 95, 110, 85, 48, 212, 140, 211, 249, 22, 79,
           200, 50, 28, 188, 52, 140, 202, 120, 68, 145, 62, 70, 184, 190, 91, 197, 152, 224, 149,
           104, 25, 178, 252, 182, 202, 182, 141, 197, 4, 81, 181, 242, 145, 42, 39, 227, 156,
           198, 225, 193, 219, 93, 122, 175, 249, 0, 175, 143, 70, 239, 46, 246, 163, 53, 163,
           109, 168, 135, 2, 235, 25, 92, 20, 145, 138, 77, 69, 166, 78, 176, 173, 212, 166, 113,
           94, 161, 41, 50, 239, 49, 111, 164, 70, 60, 2, 37, 171, 75, 136, 156, 11, 56, 42, 146,
           138, 229, 73, 146, 77, 61, 98, 196, 135, 106, 63, 197, 195, 86, 96, 203, 113, 101, 170,
           247, 181, 113, 80, 250, 108, 7, 255, 237, 129, 226, 79, 107, 112, 166, 103, 241, 24,
           223, 239, 120, 198, 58, 60, 82, 128, 3, 184, 66, 143, 224, 145, 224, 81, 206, 163, 45,
           63, 90, 168, 114, 59, 33, 159, 95, 28, 139, 123, 98, 125, 196, 15, 70, 194, 253, 54,
           14, 109, 226, 71, 17, 161, 93, 186, 87, 244, 138, 20, 52, 123, 251, 26, 36, 17, 46, 52,
           231, 232, 76, 31, 221, 84, 37, 216, 165, 212, 106, 197, 242, 98, 43, 39, 175, 254, 145,
           190, 84, 118, 222, 187, 136, 120, 163, 236, 249}

  @weapons %{
    fist: %{
      ammo: nil,
      up: :s_punchup,
      down: :s_punchdown,
      ready: :s_punch,
      attack: :s_punch1,
      flash: nil,
      slot: 1
    },
    pistol: %{
      ammo: :clip,
      up: :s_pistolup,
      down: :s_pistoldown,
      ready: :s_pistol,
      attack: :s_pistol1,
      flash: :s_pistolflash,
      slot: 2
    },
    shotgun: %{
      ammo: :shell,
      up: :s_sgunup,
      down: :s_sgundown,
      ready: :s_sgun,
      attack: :s_sgun1,
      flash: :s_sgunflash1,
      slot: 3
    },
    chaingun: %{
      ammo: :clip,
      up: :s_chainup,
      down: :s_chaindown,
      ready: :s_chain,
      attack: :s_chain1,
      flash: :s_chainflash1,
      slot: 4
    },
    missile: %{
      ammo: :misl,
      up: :s_missileup,
      down: :s_missiledown,
      ready: :s_missile,
      attack: :s_missile1,
      flash: :s_missileflash1,
      slot: 5
    },
    plasma: %{
      ammo: :cell,
      up: :s_plasmaup,
      down: :s_plasmadown,
      ready: :s_plasma,
      attack: :s_plasma1,
      flash: :s_plasmaflash1,
      slot: 6
    },
    bfg: %{
      ammo: :cell,
      up: :s_bfgup,
      down: :s_bfgdown,
      ready: :s_bfg,
      attack: :s_bfg1,
      flash: :s_bfgflash1,
      slot: 7
    },
    chainsaw: %{
      ammo: nil,
      up: :s_sawup,
      down: :s_sawdown,
      ready: :s_saw,
      attack: :s_saw1,
      flash: nil,
      slot: 1
    }
  }

  @order [:fist, :chainsaw, :pistol, :shotgun, :chaingun, :missile, :plasma, :bfg]

  @max_ammo %{clip: 200, shell: 50, cell: 300, misl: 50}
  @clip_ammo %{clip: 10, shell: 4, cell: 20, misl: 1}

  @animated_flats [
    ~w(NUKAGE1 NUKAGE2 NUKAGE3),
    ~w(FWATER1 FWATER2 FWATER3 FWATER4),
    ~w(SWATER1 SWATER2 SWATER3 SWATER4),
    ~w(LAVA1 LAVA2 LAVA3 LAVA4),
    ~w(BLOOD1 BLOOD2 BLOOD3),
    ~w(RROCK05 RROCK06 RROCK07 RROCK08),
    ~w(SLIME01 SLIME02 SLIME03 SLIME04),
    ~w(SLIME05 SLIME06 SLIME07 SLIME08),
    ~w(SLIME09 SLIME10 SLIME11 SLIME12)
  ]

  @animated_walls [
    ~w(BLODGR1 BLODGR2 BLODGR3 BLODGR4),
    ~w(SLADRIP1 SLADRIP2 SLADRIP3),
    ~w(BLODRIP1 BLODRIP2 BLODRIP3 BLODRIP4),
    ~w(FIREWALA FIREWALB FIREWALL),
    ~w(GSTFONT1 GSTFONT2 GSTFONT3),
    ~w(FIRELAVA FIRELAV3),
    ~w(FIREMAG1 FIREMAG2 FIREMAG3),
    ~w(FIREBLU1 FIREBLU2),
    ~w(ROCKRED1 ROCKRED2 ROCKRED3),
    ~w(BFALL1 BFALL2 BFALL3 BFALL4),
    ~w(SFALL1 SFALL2 SFALL3 SFALL4),
    ~w(WFALL1 WFALL2 WFALL3 WFALL4),
    ~w(DBRAIN1 DBRAIN2 DBRAIN3 DBRAIN4)
  ]

  @switches [
    {"SW1BRCOM", "SW2BRCOM"},
    {"SW1BRN1", "SW2BRN1"},
    {"SW1BRN2", "SW2BRN2"},
    {"SW1BRNGN", "SW2BRNGN"},
    {"SW1BROWN", "SW2BROWN"},
    {"SW1COMM", "SW2COMM"},
    {"SW1COMP", "SW2COMP"},
    {"SW1DIRT", "SW2DIRT"},
    {"SW1EXIT", "SW2EXIT"},
    {"SW1GRAY", "SW2GRAY"},
    {"SW1GRAY1", "SW2GRAY1"},
    {"SW1METAL", "SW2METAL"},
    {"SW1PIPE", "SW2PIPE"},
    {"SW1SLAD", "SW2SLAD"},
    {"SW1STARG", "SW2STARG"},
    {"SW1STON1", "SW2STON1"},
    {"SW1STON2", "SW2STON2"},
    {"SW1STONE", "SW2STONE"},
    {"SW1STRTN", "SW2STRTN"},
    {"SW1BLUE", "SW2BLUE"},
    {"SW1CMT", "SW2CMT"},
    {"SW1GARG", "SW2GARG"},
    {"SW1GSTON", "SW2GSTON"},
    {"SW1HOT", "SW2HOT"},
    {"SW1LION", "SW2LION"},
    {"SW1SATYR", "SW2SATYR"},
    {"SW1SKIN", "SW2SKIN"},
    {"SW1VINE", "SW2VINE"},
    {"SW1WOOD", "SW2WOOD"},
    {"SW1PANEL", "SW2PANEL"},
    {"SW1ROCK", "SW2ROCK"},
    {"SW1MET2", "SW2MET2"},
    {"SW1WDMET", "SW2WDMET"},
    {"SW1BRIK", "SW2BRIK"},
    {"SW1MOD1", "SW2MOD1"},
    {"SW1ZIM", "SW2ZIM"},
    {"SW1STON6", "SW2STON6"},
    {"SW1TEK", "SW2TEK"},
    {"SW1MARB", "SW2MARB"},
    {"SW1SKULL", "SW2SKULL"}
  ]

  @doc "Entry `index` (wrapped to `0..255`) of the random table."
  @spec random(integer()) :: 0..255
  def random(index), do: elem(@random, Bitwise.band(index, 255))

  @doc "Weapon `name`'s ammunition, states and slot."
  @spec weapon(atom()) :: map()
  def weapon(name), do: Map.fetch!(@weapons, name)

  @doc "The weapons in the order the next and previous keys cycle them."
  @spec weapon_order() :: [atom()]
  def weapon_order, do: @order

  @doc "The most of each ammunition a player carries without a backpack."
  @spec max_ammo() :: %{atom() => pos_integer()}
  def max_ammo, do: @max_ammo

  @doc "How much a clip of each ammunition holds."
  @spec clip_ammo(atom()) :: pos_integer()
  def clip_ammo(ammo), do: Map.fetch!(@clip_ammo, ammo)

  @doc "The animated flat sequences, by name."
  @spec animated_flats() :: [[String.t()]]
  def animated_flats, do: @animated_flats

  @doc "The animated wall texture sequences, by name."
  @spec animated_walls() :: [[String.t()]]
  def animated_walls, do: @animated_walls

  @doc "The texture a switch texture turns into when used, either way round, or `nil`."
  @spec switch(String.t()) :: String.t() | nil
  def switch(name) do
    Enum.find_value(@switches, fn
      {^name, other} -> other
      {other, ^name} -> other
      _pair -> nil
    end)
  end

  @doc "Every switch pair."
  @spec switches() :: [{String.t(), String.t()}]
  def switches, do: @switches
end
