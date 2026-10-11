defmodule ElixirDoom.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    ElixirDoom.Seen.create()
    Supervisor.start_link([], strategy: :one_for_one, name: ElixirDoom.Supervisor)
  end
end
