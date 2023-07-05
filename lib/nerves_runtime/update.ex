defmodule Nerves.Runtime.Update do
  @moduledoc """
  GenServer that handles device initialization.

  """
  use GenServer

  @status_app_idle "idle"

  @time_review_update 30_000

  require Logger

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def status_app(status_app), do: GenServer.cast(__MODULE__, {:status_app, status_app})

  @impl GenServer
  def init(_args) do

    Logger.warning("INIT RUNTIME")

    Process.send_after(self(), :check_fw_update, @time_review_update)

    {:ok, %{status_app: nil}}
  end

  @impl GenServer
  def handle_cast({:status_app, status_app}, state) do

    {:noreply, %{state | status_app: status_app}}
  end

  #It is checked periodically to see if greengrass wrote "true" to /root/update.conf to indicate a pending update.
  @impl GenServer
  def handle_info(:check_fw_update, %{status_app: status_app} = state) do

    case File.read("/root/update.conf") do
      {:ok, binary} ->
                        case String.replace(binary, "\n", "") do
                          "true" ->

                                    Logger.warning("PREPARE REBOOT")

                                    File.write!("/root/update.conf", "false", [:write])

                                    Process.sleep(5_000)

                                    if status_app == nil, do: Nerves.Runtime.reboot()

                          "false" -> true
                        end
      {:error, _reason} -> true
    end

    if status_app == nil, do: Process.send_after(self(), :check_fw_update, @time_review_update)

    {:noreply, state}
  end

end
