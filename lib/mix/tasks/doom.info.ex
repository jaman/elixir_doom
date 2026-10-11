defmodule Mix.Tasks.Doom.Info do
  @shortdoc "Generate ElixirDoom.Info from Doom's info.c"

  @moduledoc """
  Read the state table and thing definitions out of a GPL Doom source tree's `info.c`
  and write them as `lib/elixir_doom/info.ex`.

      mix doom.info path/to/info.c

  Every state becomes `%{picture: {sprite, frame, bright?}, tics:, action:, next:}` under
  its name as an atom (`:s_troo_stnd`), the shape `Cauldron2D.States` runs; actions are
  atoms (`:a_look`) or `nil`, and a `next` of `nil` ends the thing. Every thing type
  becomes a map under its name (`:mt_troop`) with its editor number, states, sounds as
  lump names (`"DSPOSIT1"`), speed, radius, height, mass, damage and flags as atoms.
  """

  use Mix.Task

  @fields ~w(doomednum spawn health see see_sound reaction attack_sound pain pain_chance pain_sound
             melee missile death xdeath death_sound speed radius height mass damage active_sound flags raise)a

  @state_fields ~w(spawn see pain melee missile death xdeath raise)a

  @impl Mix.Task
  def run([path]) do
    source = File.read!(path)
    states = states(source)
    things = things(source)
    File.write!("lib/elixir_doom/info.ex", render(states, things))
    Mix.shell().info("wrote #{length(states)} states and #{length(things)} thing types")
  end

  def run(_args), do: Mix.raise("usage: mix doom.info path/to/info.c")

  defp states(source) do
    ~r/\{SPR_(\w+),(\d+),(-?\d+),\{(\w+)\},(\w+),(-?\d+),(-?\d+)\},?\s*\/\/\s*(\w+)/
    |> Regex.scan(source)
    |> Enum.map(fn [_all, sprite, frame, tics, action, next, _m1, _m2, name] ->
      frame = String.to_integer(frame)

      {atom(name),
       %{
         picture: {sprite, Bitwise.band(frame, 0x7FFF), Bitwise.band(frame, 0x8000) != 0},
         tics: String.to_integer(tics),
         action: if(action == "NULL", do: nil, else: atom(action)),
         next: if(next == "S_NULL", do: nil, else: atom(next))
       }}
    end)
  end

  defp things(source) do
    [_head, table] = String.split(source, "mobjinfo_t mobjinfo[NUMMOBJTYPES] = {", parts: 2)

    ~r/\{\s*\/\/\s*(MT_\w+)(.*?)\n\s*\}/s
    |> Regex.scan(table)
    |> Enum.map(fn [_all, name, body] ->
      values =
        ~r/^\s*(.+?),?\s*\/\/\s*\w+\s*$/m
        |> Regex.scan(body)
        |> Enum.map(fn [_line, value] -> String.trim_trailing(value, ",") end)

      {atom(name),
       @fields
       |> Enum.zip(values)
       |> Map.new(fn {field, value} -> {field, value(field, value)} end)}
    end)
  end

  defp value(:flags, "0"), do: []

  defp value(:flags, value),
    do:
      value
      |> String.split("|")
      |> Enum.map(&(&1 |> String.trim() |> String.trim_leading("MF_") |> atom()))

  defp value(field, value)
       when field in [:see_sound, :attack_sound, :pain_sound, :death_sound, :active_sound] do
    case value do
      "sfx_None" -> nil
      "0" -> nil
      "sfx_" <> name -> "DS" <> String.upcase(name)
    end
  end

  defp value(_field, "S_NULL"), do: nil
  defp value(_field, "S_" <> _rest = state), do: atom(state)
  defp value(field, "0") when field in @state_fields, do: nil

  defp value(_field, value) do
    case Regex.run(~r/^(-?\d+)\s*\*\s*FRACUNIT$/, value) do
      [_all, number] -> String.to_integer(number) * 1.0
      nil -> parse_number(value)
    end
  end

  defp parse_number(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _other -> value
    end
  end

  defp atom(name), do: name |> String.downcase() |> String.to_atom()

  defp render(states, things) do
    """
    defmodule ElixirDoom.Info do
      @moduledoc \"\"\"
      Doom's state table and thing types, generated from the GPL `info.c` by
      `mix doom.info`. Do not edit by hand.

          ElixirDoom.Info.state(:s_troo_stnd)
          ElixirDoom.Info.thing(:mt_troop)
          ElixirDoom.Info.by_doomednum(3001)
      \"\"\"

      @states #{inspect(Map.new(states), limit: :infinity, printable_limit: :infinity)}

      @things #{inspect(Map.new(things), limit: :infinity, printable_limit: :infinity)}

      @doomednums @things |> Enum.filter(fn {_name, thing} -> is_integer(thing.doomednum) and thing.doomednum > 0 end) |> Map.new(fn {name, thing} -> {thing.doomednum, name} end)

      @doc "Every state by name."
      @spec states() :: %{atom() => map()}
      def states, do: @states

      @doc "State `name`."
      @spec state(atom()) :: map()
      def state(name), do: Map.fetch!(@states, name)

      @doc "Thing type `name`."
      @spec thing(atom()) :: map()
      def thing(name), do: Map.fetch!(@things, name)

      @doc "The thing type placed by editor number `number`, or `nil`."
      @spec by_doomednum(integer()) :: atom() | nil
      def by_doomednum(number), do: Map.get(@doomednums, number)
    end
    """
  end
end
