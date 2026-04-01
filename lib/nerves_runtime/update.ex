defmodule Nerves.Runtime.Update do
  @moduledoc """
  GenServer that handles device initialization and firmware OTA reboot requests.

  `/root/update.conf` with contents `true` (after trim) signals that a Greengrass
  component install (e.g. `fwup`) finished and the device should reboot into the new firmware.

  - If `in2_firmware` is **not** in the started application set: clear the flag, wait, reboot
    immediately (safety net when the app never came up).
  - If `in2_firmware` **is** running: clear the flag, wait, then reboot only when
    `status_app` is `"idle"` (operations ready, not in a transaction).

  Use `"starting"` from boot until the app is ready for OTA reboot; `"busy"` while a
  transaction is in progress. `Nerves.Runtime.Update.status_app/1` must track the same
  values as `In2Firmware.Services.Operations.Utils` (Operations syncs both).
  """

  use GenServer

  @update_conf "/root/update.conf"
  @time_review_update 10_000
  @time_review_reboot 1_000
  @status_app_idle "idle"
  @status_app_starting "starting"

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

    send(self(), :check_fw_update)

    {:ok, %{status_app: @status_app_starting, reboot_pending: false}}
  end

  @impl GenServer
  def handle_cast({:status_app, status_app}, state) do
    {:noreply, %{state | status_app: status_app}}
  end

  @impl GenServer
  def handle_info(:review_reboot, %{status_app: status_app} = state) do
    if status_app == @status_app_idle do
      Logger.warning("NERVES_RUNTIME_UPDATE_REBOOT_REQUEST")
      Nerves.Runtime.reboot()
    else
      Process.send_after(self(), :review_reboot, @time_review_reboot)
    end

    {:noreply, %{state | reboot_pending: true}}
  end

  @impl GenServer
  def handle_info(:check_fw_update, state) do
    apps = NervesMOTD.Runtime.Target.applications()
    not_started = apps[:loaded] -- apps[:started]
    firmware_not_running? = Enum.member?(not_started, :in2_firmware)

    state =
      if firmware_not_running? do
        maybe_reboot_immediate(state)
      else
        maybe_schedule_reboot_after_ota(state)
      end

    Process.send_after(self(), :check_fw_update, @time_review_update)

    {:noreply, state}
  end

  defp maybe_reboot_immediate(state) do
    case File.read(@update_conf) do
      {:ok, binary} ->
        case String.replace(binary, "\n", "") do
          "true" ->
            Logger.warning("NERVES_RUNTIME_UPDATE_PREPARE_REBOOT_FIRMWARE_NOT_RUNNING")

            case File.write(@update_conf, "false", [:write]) do
              :ok -> Logger.info("NERVES_RUNTIME_UPDATE_CONF_CLEARED")
              {:error, reason} -> Logger.error("NERVES_RUNTIME_UPDATE_CONF_WRITE #{reason}")
            end

            Process.sleep(5_000)
            Nerves.Runtime.reboot()
            state

          _ ->
            state
        end

      {:error, _} ->
        state
    end
  end

  defp maybe_schedule_reboot_after_ota(%{reboot_pending: reboot_pending} = state) do
    case File.read(@update_conf) do
      {:ok, binary} ->
        case String.replace(binary, "\n", "") do
          "true" ->
            case File.write(@update_conf, "false", [:write]) do
              :ok -> Logger.info("NERVES_RUNTIME_UPDATE_CONF_CLEARED")
              {:error, reason} -> Logger.error("NERVES_RUNTIME_UPDATE_CONF_WRITE #{reason}")
            end

            Process.sleep(5_000)

            if reboot_pending == false do
              send(self(), :review_reboot)
            end

            state

          _ ->
            state
        end

      {:error, _} ->
        state
    end
  end
end
