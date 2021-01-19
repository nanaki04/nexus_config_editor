defmodule Nexus.Meta do

  @derive Jason.Encoder
  defstruct state: :idle,
    order: 0

  def with_meta(%{} = items) do
    items
    |> Enum.reduce({0, %{}}, fn
      {:id, item}, {i, acc} ->
        {i, Map.put(acc, :id, item)}

      {:__dirty__, item}, {i, acc} ->
        {i, Map.put(acc, :__dirty__, item)}

      {:__meta__, item}, {i, acc} ->
        {i, Map.put(acc, :__meta__, item)}

      {key, %{} = item}, {0, acc} ->
        item = Map.put(item, :__meta__, %__MODULE__{order: 0, state: :opened})
        {1, Map.put(acc, key, item)}

      {key, %{} = item}, {i, acc} ->
        item = Map.put(item, :__meta__, %__MODULE__{order: i})
        {i + 1, Map.put(acc, key, item)}

      {key, item}, {0, acc} ->
        item = Map.put(%{}, item, %__MODULE__{order: 0, state: :opened})
               |> Map.put(:__meta__, %__MODULE__{order: 0, state: :opened})
        {1, Map.put(acc, key, item)}

      {key, item}, {i, acc} ->
        item = Map.put(%{}, item, %__MODULE__{order: 0, state: :opened})
               |> Map.put(:__meta__, %__MODULE__{order: i})
        {i + 1, Map.put(acc, key, item)}

    end)
    |> elem(1)
  end

  def with_meta(items) when is_list(items) do
    items
    |> Enum.with_index
    |> Enum.map(fn {k, v} -> {v, k} end)
    |> Enum.into(%{})
    |> with_meta
  end

  def with_meta_recursive(items, order \\ 0)

  def with_meta_recursive(%{} = items, order) do
    items = Enum.filter(items, fn
              {:__dirty__, _} -> false
              {:id, _} -> false
              _ -> true
            end)
            |> Enum.sort_by(fn
              {_, %{order: order}} -> order
              {_, %{index: order}} -> order
              _ -> 0
            end)
            |> Enum.with_index
            |> Enum.map(fn {{key, item}, i} -> {key, with_meta_recursive(item, i)} end)

    {head_key, head_item} = hd(items)
    head = {head_key, put_opened(head_item)}
    [head | tl(items)]
    |> Enum.into(%{})
    |> Map.put(:__meta__, %__MODULE__{order: order})
  end

  def with_meta_recursive(item, order) when is_binary(item) do
    %{}
    |> Map.put(:__meta__, %__MODULE__{order: order})
    |> Map.put(item, %{__meta__: %__MODULE__{order: 0, state: :opened}})
  end

  def with_meta_recursive(items, order) when is_list(items) do
    items
    |> Enum.with_index
    |> Enum.map(fn {item, i} -> {i, item} end)
    |> Enum.into(%{})
    |> with_meta_recursive(order)
  end

  def with_meta_recursive(item, order) do
    %{}
    |> Map.put(:__meta__, %__MODULE__{order: order})
    |> Map.put(item, %{__meta__: %__MODULE__{order: 0, state: :opened}})
  end

  def find_state(%{__meta__: %{state: state}}), do: {:ok, state}
  def find_state(_), do: :error

  def hover_first(items) do
    items
    |> Enum.map(fn
      {key, %{__meta__: %{order: 0}} = item} ->
        {key, put_hovered(item)}
      item ->
        item
    end)
    |> Enum.into(%{})
  end

  def map_state(items, state, iterator) do
    items
    |> Enum.map(fn
      {key, %{__meta__: %{state: ^state}} = item} ->
        item = case iterator.(item) do
                 {:ok, item} -> item
                 {:error, _} -> item
                 :error -> item
                 item -> item
               end

        {key, item}

      item ->
        item

    end)
    |> Enum.into(%{})
  end

  def map_selected(items, iterator), do: map_state(items, :selected, iterator)
  def map_hovered(items, iterator), do: map_state(items, :hovered, iterator)
  def map_opened(items, iterator), do: map_state(items, :opened, iterator)
  def map_idle(items, iterator), do: map_state(items, :idle, iterator)

  def map_hovered_plus_n(items, iterator, n \\ 1) do
    if has_hovered?(items) do
      count = item_count(items)
      {hovered_key, hovered} = Enum.find(items, fn
        {_, %{__meta__: %{state: :hovered}}} -> true
        _ -> false
      end)
      %{__meta__: %{order: order}} = hovered
      order = rem(count + order + n, count)

      {target_key, target} = Enum.find(items, fn
        {_, %{__meta__: %{order: ^order}}} -> true
        _ -> false
      end)

      {hovered, target} = case iterator.(hovered, target) do
        {:ok, hovered, target} ->
          {hovered, target}
        {:error, _} ->
          {hovered, target}
        :error ->
          {hovered, target}
        {hovered, target} ->
          {hovered, target}
        _ ->
          {hovered, target}
      end

      Map.put(items, hovered_key, hovered)
      |> Map.put(target_key, target)
      |> Enum.into(%{})
    else
      map_opened(items, fn item -> map_hovered_plus_n(item, iterator, n) end)
    end
  end

  def sort(items, order) do
    items
    |> Enum.sort_by(fn
      {_, %{__meta__: %{order: order}}} -> order
      _ -> 0
    end, order)
  end

  def sort_asc(items), do: sort(items, :asc)
  def sort_desc(items), do: sort(items, :desc)

  def item_count(items) do
    Enum.reduce(items, 0, fn
      {_, %{__meta__: %{order: order}}}, acc -> max(acc, order)
      _, acc -> acc
    end) + 1
  end

  def move_selected_left(items) do
    sort_desc(items)
    |> Enum.reduce({0, %{}}, fn
      {key, %{__meta__: %{order: 0}} = item}, {i, items} ->
        {i, Map.put(items, key, item)}

      {key, %{__meta__: %{order: order, state: :selected}} = item}, {_, items} ->
        item = update_meta(item, fn meta -> Map.put(meta, :order, order - 1) end)
        {1, Map.put(items, key, item)}

      {key, %{__meta__: %{order: order}} = item}, {1, items} ->
        item = update_meta(item, fn meta -> Map.put(meta, :order, order + 1) end)
        {0, Map.put(items, key, item)}

      {key, item}, {i, items} ->
        {i, Map.put(items, key, item)}

    end)
    |> sort_asc
    |> Enum.into(%{})
  end

  def update_meta(item, updater) do
    Map.update(item, :__meta__, %__MODULE__{}, updater)
  end

  def set_state(item, state) do
    update_meta(item, fn meta -> Map.put(meta, :state, state) end)
  end

  def put_hovered(item), do: set_state(item, :hovered)
  def put_selected(item), do: set_state(item, :selected)
  def put_opened(item), do: set_state(item, :opened)
  def put_idle(item), do: set_state(item, :idle)

  def move_selected_right(items) do
    count = item_count(items) - 1

    sort_asc(items)
    |> Enum.reduce({0, %{}}, fn
      {key, %{__meta__: %{order: ^count}} = item}, {i, items} ->
        {i, Map.put(items, key, item)}

      {key, %{__meta__: %{order: order, state: :selected}} = item}, {_, items} ->
        item = update_meta(item, fn meta -> Map.put(meta, :order, order + 1) end)
        {1, Map.put(items, key, item)}

      {key, %{__meta__: %{order: order}} = item}, {1, items} ->
        item = update_meta(item, fn meta -> Map.put(meta, :order, order - 1) end)
        {0, Map.put(items, key, item)}

      {key, item}, {i, items} ->
        {i, Map.put(items, key, item)}

    end)
    |> sort_asc
    |> Enum.into(%{})
  end

  def is_state?(%{__meta__: %{state: current}}, state), do: current == state
  def is_state?(_, _), do: false

  def is_hovered?(item), do: is_state?(item, :hovered)
  def has_hovered?(items), do: Enum.any?(items, fn {_, item} -> is_hovered?(item) end)

  def is_selected?(item), do: is_state?(item, :selected)
  def has_selected?(items), do: Enum.any?(items, fn {_, item} -> is_selected?(item) end)

  def is_opened?(item), do: is_state?(item, :opened)
  def has_opened?(items), do: Enum.any?(items, fn {_, item} -> is_opened?(item) end)

  def is_idle?(item), do: is_state?(item, :idle)
  def has_idle?(items), do: Enum.any?(items, fn {_, item} -> is_idle?(item) end)

  def map_hovered_recursive(items, iterator) do
    if has_hovered?(items) do
      map_hovered(items, fn
        item ->
          case iterator.(item) do
            {:ok, item} -> item
            {:error, _} -> item
            :error -> item
            item -> item
          end
      end)
    else
      map_opened(items, fn
        item -> map_hovered_recursive(item, iterator)
      end)
    end
  end

  def map_selected_recursive(items, iterator) do
    if has_selected?(items) do
      map_selected(items, fn
        item ->
          case iterator.(item) do
            {:ok, item} -> item
            {:error, _} -> item
            :error -> item
            item -> item
          end
      end)
    else
      map_opened(items, fn
        item -> map_selected_recursive(item, iterator)
      end)
    end
  end

  def select_hovered(items) do
    map_hovered_recursive(items, &put_selected/1)
  end

  def open_hovered(items) do
    map_hovered_recursive(items, &put_opened/1)
  end

  def deselect_hovered(items) do
    map_hovered_recursive(items, &put_idle/1)
  end

  def deselect_selected(items) do
    map_selected_recursive(items, &put_hovered/1)
  end

  def move_hovered_n(items, n) do
    items
    |> map_hovered_plus_n(fn hovered, target ->
      hovered = put_idle(hovered)
      target = put_hovered(target)
      {hovered, target}
    end, n)
  end

  def move_hovered_left(items), do: move_hovered_n(items, -1)
  def move_hovered_right(items), do: move_hovered_n(items, 1)

  def move_hovered_up(%{__meta__: %{state: :root}} = items) do
    if has_hovered?(items) do
      items
    else
      map_opened(items, &move_hovered_up/1)
    end
  end

  def move_hovered_up(items) do
    if has_hovered?(items) do
      map_hovered(items, &put_opened/1)
      |> put_hovered
    else
      map_opened(items, &move_hovered_up/1)
    end
  end

  def move_hovered_down(items) do
    cond do
      is_hovered?(items) && has_opened?(items) ->
        map_opened(items, &put_hovered/1)
        |> put_opened
      has_hovered?(items) ->
        map_hovered(items, &move_hovered_down/1)
      true ->
        map_opened(items, &move_hovered_down/1)
    end
  end

  def find_open_items(items, open_items \\ []) do
    open_items = open_items
                 |> Enum.reverse()
                 |> (&[items | &1]).()
                 |> Enum.reverse()

    open_item = Enum.find(items, fn
                  {_, %{__meta__: %{state: :hovered}}} -> true
                  {_, %{__meta__: %{state: :opened}}} -> true
                  {_, _} -> false
                end)

    case open_item do
      nil -> open_items
      {_, open_item} -> find_open_items(open_item, open_items)
    end
  end

end
