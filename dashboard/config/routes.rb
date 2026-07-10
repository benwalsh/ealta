Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root 'collage#show'

  # Google sign-in (OmniAuth). The request phase (POST /auth/google_oauth2) is
  # handled by the OmniAuth middleware; Google returns to the callback.
  get 'auth/:provider/callback' => 'sessions#create'
  get 'auth/failure' => 'sessions#failure'
  delete 'logout' => 'sessions#destroy', as: :logout

  # Alert subscriptions: logged-in users manage their own ("email me if you hear a
  # Corncrake"). Unsubscribe is token-authed (the one-click email link), no login.
  get    'account' => 'subscriptions#index', as: :account
  post   'subscriptions' => 'subscriptions#create'
  post   'subscriptions/cadence' => 'subscriptions#cadence', as: :subscription_cadence
  delete 'subscriptions/:id' => 'subscriptions#destroy', as: :subscription
  get    'subscriptions/:token/unsubscribe' => 'subscriptions#unsubscribe', as: :unsubscribe

  # Follow / unfollow a species from the SPA (authenticated JSON; sci_name in the
  # body so binomials needn't be URL-encoded). Backed by the same Subscription rows
  # as /account. Must stay out of the cacheable /api namespace (per-user).
  post   'favourites' => 'favourites#create'
  delete 'favourites' => 'favourites#destroy'

  # On-demand facts & folklore for a bird — the card's "look it up now" for a signed-in
  # viewer. Authed + CSRF (it triggers a real sourcing run), so out of the /api cache.
  post 'species/:sci/enrichment' => 'enrichment#create', constraints: { sci: %r{[^/]+} }

  # Admin-only health panel (User#admin?, fail-closed). Not linked publicly.
  get 'admin' => 'admin#index', as: :admin
  # Change the station's runtime settings (its display language).
  patch 'admin/station' => 'admin#update_station', as: :admin_station
  # Mutating maintenance actions (each admin-gated) — the ones that used to be shell/PHP.
  post 'admin/birdnet/restart' => 'admin#restart_listener', as: :admin_restart_listener
  patch 'admin/detection' => 'admin#correct_detection', as: :admin_correct_detection
  delete 'admin/data' => 'admin#clear_data', as: :admin_clear_data

  # The background-jobs dashboard (Solid Queue via Mission Control). Admin-gated by
  # JobsBaseController; cloud-only, so guarded — the gem isn't installed on the Pi.
  mount MissionControl::Jobs::Engine, at: '/jobs' if defined?(MissionControl::Jobs::Engine)

  # The Pi's lazy push lands here (cloud mirror only; 404 on the Pi). Token-authed.
  post 'ingest/detections' => 'ingest#detections'
  post 'ingest/heartbeats' => 'ingest#heartbeats'

  # JSON API for the React SPA (and, later, a public API host). Read-only GETs.
  namespace :api do
    get 'overview' => 'overview#show'
    get 'journal' => 'journal#show'
    get 'stats' => 'stats#show'
    get 'directory' => 'directory#show'
    get 'species/:sci' => 'species#show', constraints: { sci: %r{[^/]+} }
  end

  get 'panel' => 'collage#panel'
  # The three surfaces, "opposite of mobile-first" — richest at the root, more
  # constrained as they specialise:
  #   /        the full experience (chrome + nav) — see root above
  #   /kiosk   no chrome, the four cards cycling, for a passive monitor/iPad
  #   /station the single collage screen in the house style, tuned for the Inky
  get 'kiosk' => 'collage#kiosk'
  # /station = the clean 480×800 device pixels (the panel + shooter target).
  # /station/preview = the same screen wrapped in a timber frame + e-ink emulation.
  get 'station' => 'collage#station'
  get 'station/preview' => 'collage#station_preview', as: :station_preview
  # The station's own mark and favicon, streamed from its profile directory — they live
  # outside app/assets, so the pipeline can't serve them. See StationAssetsController.
  get 'station/brand/:kind' => 'station_assets#show', as: :station_brand
  # Bird illustrations, likewise from the profile (the engine ships none). format: false
  # keeps the ".png" inside :name instead of Rails parsing it as a response format.
  get 'birds/:name' => 'station_assets#bird', as: :bird_image,
      constraints: { name: /[a-z0-9-]+\.png/ }, format: false
  # A browser mock-up of the physical Inky Impression 7.3" panel: fetches /panel
  # and applies the same Spectra-6 dither the real glass gets.
  get 'emulator' => 'collage#emulator'
  # Stats, the species directory, and species detail are now tabs + a modal inside
  # the React SPA at `/`, served by /api/stats, /api/directory, /api/species/:sci.
end
