# Admin-only surface, never linked from the public chrome. Gated by User#admin?
# (ADMIN_EMAILS, fail-closed). Session-authed like /account; kept out of the
# cookie-free /api and out of the CloudFront cache (see cdn.tf).
class AdminController < ApplicationController
  before_action :require_admin

  # The health panel — "is the box alive?" HTML boots the React SPA with the admin panel
  # pre-opened (a hard nav to /admin); JSON feeds that panel. All figures come from AdminHealth.
  def index
    respond_to do |format|
      format.html do
        @bootstrap = spa_bootstrap(open_panel: 'admin')
        render 'collage/show', layout: 'editorial'
      end
      format.json { render json: AdminSerializer.health(AdminHealth.snapshot) }
    end
  end

  # Change the wall's display language (the one setting that shouldn't need a redeploy).
  # Anything invalid is ignored — the panel keeps its current language.
  def update_station
    Station.language = params.require(:station).fetch(:language)
    respond_admin({ ok: true, message: "Wall language set to #{Station.language_name(Station.language)}." })
  rescue ArgumentError, ActionController::ParameterMissing, KeyError
    respond_admin({ ok: false, message: 'Unknown language.' })
  end

  # Restart the detection listener (the thing you'd otherwise SSH in for). No-op off the Pi.
  def restart_listener
    respond_admin(ListenerControl.restart)
  end

  # Relabel a mis-identified detection to the correct species.
  def correct_detection
    detection = params.require(:detection)
    respond_admin(DetectionCorrection.apply(detection.fetch(:id), sci_name: detection.fetch(:sci_name)))
  rescue ActionController::ParameterMissing, KeyError
    respond_admin({ ok: false, message: 'Provide a detection id and scientific name.' })
  end

  # Wipe the detection history — guarded by a typed confirmation (params[:confirm] == 'DELETE').
  def clear_data
    respond_admin(DataReset.clear!(confirm: params[:confirm]))
  end

  private

  # One reply for every mutating admin action. HTML flashes the { ok:, message: } result and
  # redirects back to the panel; JSON returns it verbatim (422 when not ok) for the SPA to show
  # inline. flash.now matches the previous behaviour on the HTML path.
  def respond_admin(result)
    respond_to do |format|
      format.html do
        flash.now[result[:ok] ? :notice : :alert] = result[:message]
        redirect_to admin_path
      end
      format.json { render json: result, status: (result[:ok] ? :ok : :unprocessable_content) }
    end
  end

  # Non-admins (signed in or not) are bounced home on a hard nav; the SPA's health fetch gets a
  # 403 to handle client-side (without it, a 302 to an HTML body would be parsed as JSON).
  def require_admin
    return if current_user&.admin?

    respond_to do |format|
      format.json { head :forbidden }
      format.any  { redirect_to root_path }
    end
  end
end
