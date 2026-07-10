class SessionsController < ApplicationController
  # The OmniAuth callback: find-or-create the user and start a session.
  def create
    user = User.from_omniauth(request.env['omniauth.auth'])
    session[:user_id] = user.id
    redirect_to root_path, notice: "Signed in as #{user.display_name}"
  end

  def destroy
    reset_session
    redirect_to root_path, notice: 'Signed out' # rubocop:disable Rails/I18nLocaleTexts
  end

  # OmniAuth failure (denied consent, misconfig, abandoned flow) lands here.
  def failure
    redirect_to root_path, alert: 'Sign-in was cancelled or failed' # rubocop:disable Rails/I18nLocaleTexts
  end
end
