defmodule NexusWeb.LibraryLive do
  use NexusWeb, :live_view
  alias Nexus.Meta

  '''
  %{
    "projects" => %{
      __meta__: %{
        selected: false,
        hovered: false,
        order: 0
      }
    }
  }
  '''

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, state: %{})
             |> connect_to_library
             |> read_domains
             |> build_render_data

    {:ok, socket}
  end

  defp build_render_data(%{assigns: %{state: state}} = socket) do
    render_data = Meta.find_open_items(state)
                  |> Enum.map(fn row ->
                    Enum.filter(row, fn
                      {:__dirty__, _} -> false
                      {:id, _} -> false
                      _ -> true
                    end)
                    |> Enum.map(fn {key, item} -> {key, Meta.find_state(item)} end)
                    |> Enum.filter(fn
                      {_, {:ok, _}} -> true
                      _ -> false
                    end)
                    |> Enum.map(fn {key, {:ok, state}} -> {key, state} end)
                    |> Enum.into(%{})
                  end)

    assign(socket, render: render_data)
  end

  defp build_render_data(socket) do
    assign(socket, render: [])
  end

  defp noreply(socket), do: {:noreply, socket}

  defp map_state(%{assigns: %{state: state}} = socket, iterator) do
    state = case iterator.(state) do
              {:ok, state} -> state
              {:error, _} -> state
              :error -> state
              state -> state
            end

    assign(socket, state: state)
  end

  defp map_state(socket, _), do: socket

  @impl true
  def handle_event("key_up", %{"key" => "h"}, socket) do
    map_state(socket, &Meta.move_hovered_left/1)
    |> build_render_data
    |> noreply
  end

  def handle_event("key_up", %{"key" => "l"}, socket) do
    map_state(socket, &Meta.move_hovered_right/1)
    |> build_render_data
    |> noreply
  end

  def handle_event("key_up", %{"key" => "j"}, socket) do
    map_state(socket, &Meta.move_hovered_down/1)
    |> build_render_data
    |> noreply
  end

  def handle_event("key_up", %{"key" => "k"}, socket) do
    map_state(socket, &Meta.move_hovered_up/1)
    |> build_render_data
    |> noreply
  end

  def handle_event(_, _, socket) do
    {:noreply, socket}
  end

  defp connect_to_library(socket) do
    with :pong <- Node.ping(:"library@jan-VirtualBox"),
         :ok <- :global.sync()
    do
      assign(socket, library: {:global, Library})
    else
      err ->
        IO.inspect(err)
        socket
    end
  end

  defp read_domains(%{assigns: %{library: library}} = socket) do
    {:ok, domains} = GenServer.call(library, {:read, "domains"})
    state = socket.assigns.state
    domain_items = Enum.filter(domains, fn
                     {:__dirty__, _} -> false
                     {:id, _} -> false
                     _ -> true
                   end)
                   |> Enum.sort_by(&elem(&1, 1))
                   |> Enum.map(fn {key, _} -> {key, read_domain(key, library)} end)
                   |> Enum.into(%{})
                   |> Meta.with_meta_recursive
                   |> Meta.hover_first
                   |> Meta.set_state(:root)

    assign(socket, state: domain_items)
  end

  defp read_domains(socket) do
    socket
  end

  defp read_domain(domain, library) do
    with {:ok, content} <- GenServer.call(library, {:read, domain})
    do
      content
    else
      _ ->
        %{}
    end
  end

  defp add_meta_to_domain("domains", content) do
    Meta.with_meta(content)
  end

  defp add_meta_to_domain("projects", content) do
    # TODO
    Meta.with_meta(content)
  end

  defp add_meta_to_domain(domain, content) do
    IO.inspect(domain)
    IO.inspect(content)
    content
  end

  def class({_, :selected}), do: "select"
  def class({_, :hovered}), do: "hover"
  def class({_, :opened}), do: "normal open"
  def class(_), do: "normal"

  defp read_projects(%{assigns: %{library: library}} = socket) do
    {:ok, projects} = GenServer.call(library, {:read, "projects"})
    projects = Jason.encode!(projects)
    assign(socket, projects: projects)
  end

  defp read_projects(socket), do: socket
end
