defmodule Nerves.Runtime.Update do
  @moduledoc """
  GenServer that handles device initialization.

  """
  use GenServer

  @path "/home/ggc_user/"
  @file_green_grass "Greengrass.jar"
  @file_config "config.yaml"
  @file_device "device.pem.crt"
  @file_private "private.pem.key"
  @file_ca "CA.pem"

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

    Process.send_after(self(), :check_ggc, @time_review_update)

    {:ok, %{status_app: nil}}
  end

  @impl GenServer
  def handle_cast({:status_app, status_app}, state) do

    {:noreply, %{state | status_app: status_app}}
  end

  #It is checked periodically to see if greengrass wrote "true" to /root/update.conf to indicate a pending update.
  @impl GenServer
  def handle_info(:check_fw_update, state) do

  apps = NervesMOTD.Runtime.Target.applications()

  not_started = Enum.join(apps[:loaded] -- apps[:started], ", ")

  if String.contains?(not_started, "in2_firmware") do

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

  @impl GenServer
  def handle_info(:check_ggc, state) do

    args =
      [
        "-c",
        "java -Droot='/home/ggc_user' -Dlog.store=FILE -jar /home/ggc_user/Greengrass.jar --init-config /home/ggc_user/config.yaml --component-default-user root:root --setup-system-service false"
        ]

    {result, _ } = System.shell("ps")

    if review_files() == true and String.contains?(result, "java -Droot=" ) == false do
      spawn(fn -> MuonTrap.cmd("sh", args, into: IO.stream(:stdio, :line)) end)
    end

    {:noreply, state}
  end

  defp review_files() do

    if File.exists?(@path <> @file_green_grass) == true and
       File.exists?(@path <> @file_config) == true and
       File.exists?(@path <> @file_device)  == true and
       File.exists?(@path <> @file_ca) == true and
       File.exists?(@path <> @file_private) == true do

      true
    else
      false
    end

  end

end
