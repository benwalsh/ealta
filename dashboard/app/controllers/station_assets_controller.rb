# Serves the station's brand assets — the masthead mark and the favicon — out of the
# active profile directory.
#
# Profile files live outside app/assets, so the asset pipeline cannot see them and
# `asset_path` would raise. A symlink would work locally but is awkward in the cloud
# image, where the profile is staged at build time; a controller keeps one mechanism
# for both. Only two keys are servable, resolved through Station — never a
# caller-supplied path, so there is no traversal surface.
class StationAssetsController < ApplicationController
  KINDS = %w[mark favicon].freeze

  def show
    return head :not_found unless KINDS.include?(params[:kind])

    path = Station.brand_asset(params[:kind])
    return head :not_found if path.nil?

    # The profile is fixed for the life of the process, so this is safe to cache hard.
    expires_in 1.hour, public: true
    send_file path, type:        Rack::Mime.mime_type(path.extname, 'application/octet-stream'),
                    disposition: 'inline'
  end

  # GET /birds/<slug>.png — a bird illustration from the station's profile. This used to
  # be a symlink at public/birds; the art now lives with the station whose style produced
  # it, so it is served rather than statically linked. The route constrains :name to a
  # slug + .png, and we take only its basename, so nothing escapes the art directory.
  # URLs are unchanged (`/birds/<slug>.png?v=<mtime>`); only the source of the bytes is.
  #
  # Bytes resolve local-first, then remote: if the profile has the file on disk (dev, and
  # the Pi after it syncs the art to its SD card) it is streamed; otherwise, when the
  # station publishes its art to a CDN (ILLUSTRATIONS_BASE_URL — e.g. an S3+CloudFront
  # bucket), we redirect there. That is how the cloud image stays slim — the 225 MB of art
  # lives on the CDN, not baked into the image. With no local file and no base URL, it is a
  # 404 exactly as before.
  def bird
    name = File.basename(params[:name])
    dir  = StationProfile.illustrations_dir

    if dir && (path = dir.join(name)).file?
      expires_in 1.week, public: true
      return send_file path, type: 'image/png', disposition: 'inline'
    end

    base = ENV['ILLUSTRATIONS_BASE_URL'].presence
    return head :not_found if base.nil?

    expires_in 1.day, public: true
    redirect_to "#{base.chomp('/')}/#{name}", allow_other_host: true, status: :found
  end
end
