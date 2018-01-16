defmodule ThySupervisor do
  use GenServer

  require IEx

  #######
  # API #
  #######

  def start_link(child_spec_list) do
    GenServer.start_link(__MODULE__, [child_spec_list])
  end

  def start_child(supervisor, child_spec) do
    GenServer.call(supervisor, {:start_child, child_spec})
  end

  def terminate_child(supervisor, pid) when is_pid(pid) do
    GenServer.call(supervisor, {:terminate_child, pid})
  end

  def restart_child(supervisor, pid, child_spec) when is_pid(pid) do
    GenServer.call(supervisor, {:restart_child, pid, child_spec})
  end

  def count_children(supervisor) do
    GenServer.call(supervisor, :count_children)
  end

  def which_children(supervisor) do
    GenServer.call(supervisor, :which_children)
  end

  ######################
  # Callback Functions #
  ######################

  def init([child_spec_list]) do
    Process.flag(:trap_exit, true)
    state = child_spec_list
              |> start_children
              |> Enum.into(%{})

    {:ok, state}
  end

  def handle_call({:start_child, child_spec}, _from, state) do
    case start_child(child_spec) do
      {:ok, pid} ->
        new_state = state |> Map.put(pid, child_spec)
        {:reply, {:ok, pid}, new_state}
      :error ->
        {:reply, {:error, "error starting child"}, state}
    end
  end

  def handle_call({:terminate_child, pid}, _from, state) do
    case terminate_child(pid) do
      :ok ->
        new_state = state |> Map.delete(pid)
        {:reply, :ok, new_state}
      :error ->
        {:reply, {:error, "error terminating child"}, state}
    end
  end

  # Original
  # def handle_call({:restart_child, old_pid, _child_spec}, _from, state) do
  #   IO.inspect(old_pid)
  #   IO.inspect(state)
  #   case Map.fetch(state, old_pid) do
  #     {:ok, child_spec} ->
  #       case restart_child(old_pid, child_spec) do
  #         {:ok, {pid, child_spec}} ->
  #           new_state = state
  #                         |> Map.delete(old_pid)
  #                         |> Map.put(pid, child_spec)
  #           {:reply, {:ok, pid}, new_state}
  #         :error ->
  #           {:reply, {:error, "error restarting child"}, state}
  #         unexpected ->
  #           IO.puts "Got unexpected value 1 #{inspect(unexpected)}"
  #       end
  #     # _ ->
  #     #   {:reply, :ok, state}
  #     unexpected ->
  #       IO.puts "Got unexpected value 2 #{inspect(unexpected)}"
  #   end
  # end

  # Refactored as in http://relistan.com/elixir-thoughts-on-the-with-statement/
  def handle_call({:restart_child, old_pid, child_spec}, _from, state) do
    with {:ok, _old_child_spec} <- Map.fetch(state, old_pid),
         {:ok, {pid, child_spec}} <- restart_child(old_pid, child_spec) do
            new_state = state
                          |> Map.delete(old_pid)
                          |> Map.put(pid, child_spec)
            {:reply, {:ok, pid}, new_state}
    else
      :error ->
        {:reply, {:error, "error restarting child"}, state}
      _ ->
        {:reply, :ok, state}
    end
  end

  def handle_call(:count_children, _from, state) do
    {:reply, Map.size(state), state}
  end

  def handle_call(:which_children, _from, state) do
    {:reply, state, state}
  end

  def handle_info({:EXIT, from, :normal}, state) do
    new_state = state |> Map.delete(from)
    {:noreply, new_state}
  end

  def handle_info({:EXIT, from, :killed}, state) do
    new_state = state |> Map.delete(from)
    {:noreply, new_state}
  end

  def handle_info({:EXIT, old_pid, _reason}, state) do
    case Map.fetch(state, old_pid) do
      {:ok, child_spec} ->
        case restart_child(old_pid, child_spec) do
          {:ok, {pid, child_spec}} ->
            new_state = state
                          |> Map.delete(old_pid)
                          |> Map.put(pid, child_spec)
            {:noreply, new_state}
          :error ->
            {:noreply, state}
        end
      _ ->
        {:noreply, state}
    end
  end

  def terminate(_reason, state) do
    terminate_children(state)
    :ok
  end

  #####################
  # Private Functions #
  #####################

  defp start_children([child_spec|rest]) do
    case start_child(child_spec) do
      {:ok, pid} ->
        [{pid, child_spec}|start_children(rest)]
      :error ->
        :error
    end
  end

  defp start_children([]), do: []

  defp start_child({mod, fun, args}) do
    case apply(mod, fun, args) do
      pid when is_pid(pid) ->
        Process.link(pid)
        {:ok, pid}
      _ ->
        :error
    end
  end

  defp terminate_children([]) do
    :ok
  end

  defp terminate_children(child_specs) do
    child_specs |> Enum.each(fn {pid, _} -> terminate_child(pid) end)
  end

  defp terminate_child(pid) do
    Process.exit(pid, :kill)
    :ok
  end

  # Original
  # defp restart_child(pid, child_spec) when is_pid(pid) do
  #   case terminate_child(pid) do
  #     :ok ->
  #       case start_child(child_spec) do
  #         {:ok, new_pid} ->
  #           {:ok, {new_pid, child_spec}}
  #         :error ->
  #           :error
  #       end
  #     :error ->
  #       :error
  #   end
  # end

  # Refactored
  defp restart_child(pid, child_spec) when is_pid(pid) do
    with :ok           <- terminate_child(pid),
        {:ok, new_pid} <- start_child(child_spec) do
           {:ok, {new_pid, child_spec}}
    else
      :error ->
        :error
    end
  end

end

# iex(7)> {:ok, sup_pid} = ThySupervisor.start_link([])
# {:ok, #PID<0.125.0>}
# iex(8)> {:ok, child_pid} = ThySupervisor.start_child(sup_pid, {ThyWorker, :start_link, []})
# {:ok, #PID<0.127.0>}
# iex(9)> ThySupervisor.which_children(sup_pid)
# %{#PID<0.127.0> => {ThyWorker, :start_link, []}}
# iex(10)> {:ok, new_child_pid} = ThySupervisor.restart_child(sup_pid, child_pid, {NewWorker, :start_link, []})
# {:ok, #PID<0.130.0>}
# iex(11)> ThySupervisor.which_children(sup_pid)
# %{#PID<0.130.0> => {NewWorker, :start_link, []}}
