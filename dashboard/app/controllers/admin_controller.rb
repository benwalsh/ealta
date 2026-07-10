# Admin-only surface, never linked from the public chrome. Gated by User#admin?
# (ADMIN_EMAILS, fail-closed). Session-authed like /account; kept out of the
# cookie-free /api and out of the CloudFront cache (see cdn.tf).
class AdminController < ApplicationController
  before_action :require_admin

  # The health panel — "is the box alive?" All figures come from AdminHealth.
  def index
    @health = AdminHealth.snapshot
    @station_language = Station.language
  end

  # Change the wall's display language (the one setting that shouldn't need a redeploy).
  # Anything invalid is ignored — the panel keeps its current language.
  def update_station
    Station.language = params.require(:station).fetch(:language)
    redirect_to admin_path
  rescue ArgumentError, ActionController::ParameterMissing, KeyError
    redirect_to admin_path
  end

  # Restart the detection listener (the thing you'd otherwise SSH in for). No-op off the Pi.
  def restart_listener
    flash_result(ListenerControl.restart)
    redirect_to admin_path
  end

  # Relabel a mis-identified detection to the correct species.
  def correct_detection
    detection = params.require(:detection)
    flash_result(DetectionCorrection.apply(detection.fetch(:id), sci_name: detection.fetch(:sci_name)))
    redirect_to admin_path
  rescue ActionController::ParameterMissing, KeyError
    redirect_to admin_path
  end

  # Wipe the detection history — guarded by a typed confirmation (params[:confirm] == 'DELETE').
  def clear_data
    flash_result(DataReset.clear!(confirm: params[:confirm]))
    redirect_to admin_path
  end

  private

  # A service object's { ok:, message: } result → a flash notice or alert.
  def flash_result(result)
    flash.now[result[:ok] ? :notice : :alert] = result[:message]
  end

  # Non-admins (signed in or not) are bounced home — the page isn't advertised.
  def require_admin
    redirect_to root_path unless current_user&.admin?
  end
end
