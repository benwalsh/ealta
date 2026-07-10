class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # The time-range window shared by every view (the top picker). Hours; a huge
  # value means "all time".
  WINDOWS = [['1H', 1], ['12H', 12], ['24H', 24], ['7D', 168], ['ALL', 1_000_000]].freeze

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end
  helper_method :current_user

  def logged_in?
    current_user.present?
  end
  helper_method :logged_in?

  # Gate an authenticated action. JSON callers (the SPA's follow toggle) get a 401
  # to handle client-side; HTML callers are bounced to the front page.
  def require_login
    return if logged_in?

    respond_to do |format|
      format.json { head :unauthorized }
      format.any  { redirect_to root_path }
    end
  end

  # sci_names the current user follows (their active 'species' subscriptions). Seeds
  # the React bootstrap so the Directory/modal show the follow state on first paint.
  def followed_sci_names
    return [] unless current_user

    current_user.subscriptions.active.where(alert_type: 'species').pluck(:sci_name)
  end
  helper_method :followed_sci_names

  # The chosen UI-chrome language ("en"/"ga"), from the toggle's cookie. Default
  # English. Seeds <html data-lang> and the React bootstrap.
  def ui_lang
    %w[en ga].include?(cookies[:ui_lang]) ? cookies[:ui_lang] : 'en'
  end
  helper_method :ui_lang

  # The signed-in user as a JSON-able hash for the React bootstrap, or nil.
  def user_payload
    return nil unless current_user

    { name: current_user.display_name, email: current_user.email,
      avatar_url: current_user.avatar_url, admin: current_user.admin? }
  end

  def current_window
    valid = WINDOWS.map { |_label, hours| hours }
    valid.include?(params[:h]&.to_i) ? params[:h].to_i : 24
  end
  helper_method :current_window

  def window_label
    WINDOWS.find { |_label, hours| hours == current_window }&.first
  end
  helper_method :window_label

  # Human phrase for the caption's windowed count ("… 12 calls today").
  def window_phrase
    { 1 => 'in the last hour', 12 => 'in the last 12 hours', 24 => 'today',
      168 => 'this week', 1_000_000 => 'all-time' }.fetch(current_window, 'recently')
  end
  helper_method :window_phrase
end
