defmodule OliE2E.Helpers do
  @moduledoc "Small stand-ins for JS idioms the client has no equivalent of."

  @doc """
  A run id for scenario seeds (`-${Date.now()}-${process.pid}` in JS). The modules share
  one OS pid, so a number unique in the VM is added. It goes first because Torus
  slugifies only a title's first 30 characters: project slugs then differ too.
  """
  def run_id do
    unique =
      System.unique_integer([:positive])
      |> rem(1000)
      |> Integer.to_string()
      |> String.pad_leading(3, "0")

    random = :rand.uniform(10_000) |> Integer.to_string() |> String.pad_leading(5, "0")
    "-#{unique}#{random}-#{System.os_time(:millisecond)}-#{System.pid()}"
  end
end
