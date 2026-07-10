# Restart the detection listener from the admin panel — the one service most likely to wedge on
# an unattended box, and the thing you'd otherwise SSH in to do. On the Pi, Rails runs as `pi`
# and restarts the unit through a narrow sudoers rule (added by deploy/provision.sh); anywhere
# systemctl or the unit isn't present (macOS dev, the cloud mirror) it's a safe no-op that says
# so. Replaces scripts/restart_services.sh + the PHP service_controls.
class ListenerControl
  UNIT = ENV.fetch('LISTENER_UNIT', 'ealta-listener.service')

  class << self
    def restart
      return { ok: false, message: "restart unavailable here (no systemctl for #{UNIT})" } unless available?

      if system('sudo', '-n', 'systemctl', 'restart', UNIT)
        { ok: true, message: "restarted #{UNIT}" }
      else
        { ok: false, message: "could not restart #{UNIT} (check the sudoers rule)" }
      end
    end

    # True only when systemctl exists AND the unit is installed (`cat` exits 0 iff the unit
    # file is present; on macOS there's no systemctl at all, so system() returns nil → false).
    def available?
      system('systemctl', 'cat', UNIT, out: File::NULL, err: File::NULL) || false
    end
  end
end
