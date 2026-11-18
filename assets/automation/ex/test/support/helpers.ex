defmodule OliE2E.Helpers do
  @moduledoc "Small stand-ins for JS idioms the client has no equivalent of."

  @doc """
  A run id for scenario seeds (`-${Date.now()}-${process.pid}` in JS). Torus slugifies
  the first 30 characters of a title, so the distinguishing digits go first: modules
  that seed in the same millisecond would otherwise collide on the slug.
  """
  def run_id do
    unique = System.unique_integer([:positive]) |> rem(1000) |> Integer.to_string() |> String.pad_leading(3, "0")
    random = :rand.uniform(10_000) |> Integer.to_string() |> String.pad_leading(5, "0")
    "-#{unique}#{random}-#{System.os_time(:millisecond)}-#{System.pid()}"
  end
end
