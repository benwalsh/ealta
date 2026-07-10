# The base controller Mission Control Jobs' dashboard inherits from, so the whole
# /jobs surface is gated exactly like /admin — signed in AND User#admin? (fail-closed),
# never advertised. We disable Mission Control's own HTTP basic auth in favour of this
# (see config/initializers/mission_control_jobs.rb).
class JobsBaseController < ApplicationController
  before_action :require_admin

  private

  def require_admin
    redirect_to root_path unless current_user&.admin?
  end
end
