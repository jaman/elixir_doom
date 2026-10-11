defmodule ElixirDoom.Sounds do
  @moduledoc """
  Doom's sound effects — the `DS*` lumps, 8-bit DMX recordings — as `TuningFork` voices.

      ElixirDoom.Sounds.voice("DSPISTOL")

  A lump is decoded the first time it is asked for and kept. A name the WAD lacks gives
  `nil`, which plays nothing.
  """

  alias ElixirDoom.{Assets, Wad}
  alias TuningFork.{Sample, Voice}

  @doc "The voice for sound lump `name`, or `nil`."
  @spec voice(String.t()) :: Voice.t() | nil
  def voice(name) do
    key = {__MODULE__, name}

    case :persistent_term.get(key, :unread) do
      :unread ->
        voice = decode(name)
        :persistent_term.put(key, voice)
        voice

      voice ->
        voice
    end
  end

  defp decode(name) do
    with true <- Assets.loaded?(),
         <<3::little-16, rate::little-16, count::little-32, data::binary>> <-
           Wad.lump(Assets.get().wad, name),
         true <- byte_size(data) >= count do
      pcm =
        for <<byte <- trim(binary_part(data, 0, count))>>,
          into: <<>>,
          do: <<(byte - 128) * 256::16-signed-little>>

      sample = Sample.from_pcm(pcm, rate: rate, root: 440.0, name: name)
      Voice.new(sample: sample, freq: 440.0, gain: 0.8)
    else
      _missing -> nil
    end
  end

  defp trim(data) when byte_size(data) > 32, do: binary_part(data, 16, byte_size(data) - 32)
  defp trim(data), do: data
end
