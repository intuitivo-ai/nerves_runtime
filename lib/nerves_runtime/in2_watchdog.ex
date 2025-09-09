defmodule Nerves.Runtime.In2Watchdog do
  @moduledoc false

  use GenServer

  require Logger

  @check_interval_ms 20_000
  @reboot_after_ms 600_000

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl GenServer
  def init(_args) do
    Process.send_after(self(), :tick, @check_interval_ms)
    {:ok, %{in2_not_started_since: nil}}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    apps = NervesMOTD.Runtime.Target.applications()
    not_started = apps[:loaded] -- apps[:started]

    state = maybe_handle_in2_not_started(not_started, state)

    Process.send_after(self(), :tick, @check_interval_ms)
    {:noreply, state}
  end

  defp maybe_handle_in2_not_started(not_started, state) do
    if Enum.member?(not_started, :in2_firmware) do
      now_ms = System.monotonic_time(:millisecond)

      cond do
        is_nil(state.in2_not_started_since) ->
          Map.put(state, :in2_not_started_since, now_ms)

        now_ms - state.in2_not_started_since >= @reboot_after_ms ->
          Logger.warning("IN2_FIRMWARE_NOT_STARTED_FOR_10MIN_REBOOT")
          Nerves.Runtime.reboot()
          state

        true ->
          state
      end
    else
      if state.in2_not_started_since != nil do
        Map.put(state, :in2_not_started_since, nil)
      else
        state
      end
    end
  end
end


