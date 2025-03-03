defmodule Appsignal.Monitor do
  @moduledoc false
  @deletion_delay Application.get_env(:appsignal, :deletion_delay, 5_000)
  @sync_interval Application.get_env(:appsignal, :sync_interval, 60_000)

  use GenServer
  alias Appsignal.Tracer

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(state) do
    schedule_sync()

    {:ok, state}
  end

  def add do
    GenServer.cast(__MODULE__, {:monitor, self()})
  end

  def handle_cast({:monitor, pid}, monitors) do
    if pid in monitors do
      {:noreply, monitors}
    else
      Process.monitor(pid)
      {:noreply, [pid | monitors]}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _}, monitors) do
    Process.send_after(self(), {:delete, pid}, @deletion_delay)
    {:noreply, monitors}
  end

  def handle_info({:delete, pid}, monitors) do
    Tracer.delete(pid)
    {:noreply, List.delete(monitors, pid)}
  end

  def handle_info(:sync, _monitors) do
    schedule_sync()

    pids = monitored_pids()

    Appsignal.Logger.debug("Synchronizing monitored PIDs in Appsignal.Monitor (#{length(pids)})")

    {:noreply, pids}
  end

  def child_spec(_) do
    %{
      id: Appsignal.Monitor,
      start: {Appsignal.Monitor, :start_link, []}
    }
  end

  defp monitored_pids do
    {:monitors, monitors} = Process.info(self(), :monitors)
    Enum.map(monitors, fn {:process, process} -> process end)
  end

  defp schedule_sync do
    Process.send_after(self(), :sync, @sync_interval)
  end
end
