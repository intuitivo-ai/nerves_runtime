defmodule Nerves.Runtime.Update do
  @moduledoc """
  GenServer that handles device initialization.

  """
  use GenServer

  @time_review_update 20_000

  require Logger

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def status_app(status_app), do: GenServer.cast(__MODULE__, {:status_app, status_app})

  @impl GenServer
  def init(_args) do

    Logger.warning("INIT_RUNTIME")

    System.shell("mount -o remount,exec /tmp")

    Process.send_after(self(), :check_fw_update, @time_review_update)

    {:ok, %{status_app: nil}}
  end

  @impl GenServer
  def handle_cast({:status_app, status_app}, state) do

    {:noreply, %{state | status_app: status_app}}
  end

  # Periodically checks /root/update.conf for a pending firmware reboot request ("true").
  @impl GenServer
  def handle_info(:check_fw_update, state) do

  apps = NervesMOTD.Runtime.Target.applications()

  not_started = apps[:loaded] -- apps[:started]

  if Enum.member?(not_started, :in2_firmware) do

    case File.read("/root/update.conf") do
      {:ok, binary} ->
                        case String.replace(binary, "\n", "") do
                          "true" ->

                                    Logger.warning("PREPARE_RUNTIME_REBOOT")

                                    case File.write("/root/update.conf", "false", [:write]) do
                                      :ok -> Logger.info("MAIN_SERVICES_RUNTIME_UPDATE_WRITE")
                                      {:error, reason} -> Logger.error("MAIN_SERVICES_RUNTIME_UPDATE_WRITE #{reason}")
                                    end

                                    Process.sleep(5_000)

                                    Nerves.Runtime.reboot()

                          "false" -> true
                        end
      {:error, _reason} -> true
    end
end

    Process.send_after(self(), :check_fw_update, @time_review_update)

    {:noreply, state}
  end

end
