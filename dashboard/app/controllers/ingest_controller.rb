# The cloud mirror's write side: the Pi's push.py POSTs batches of detections
# here and we upsert them into the cloud DB. Stateless + token-authed (no
# session, no CSRF — hence ActionController::API). Disabled (404) unless
# CLOUD_INGEST_TOKEN is set, so on the Pi (token unset) it accepts nothing.
class IngestController < ActionController::API
  # Only the listener's own columns; the cloud assigns its own id + timestamps.
  UPSERT_COLUMNS = %w[Date Time Sci_Name Com_Name Confidence Lat Lon Week File_Name dedupe_key].freeze
  # A liveness tick's columns; dedupe_key (SHA-256 of at|source) is the upsert target.
  HEARTBEAT_COLUMNS = %w[at source dedupe_key].freeze
  # Keep the mirror's ticks bounded like the Pi's — they only feed the recent window.
  HEARTBEAT_RETENTION = 2.days
  # The scalar half of a vitals report. `at` is the device's collection time; everything else
  # is named for the column it lands in. `services` is absent here — it's a nested, open-keyed
  # hash and is permitted separately (see permitted_services).
  VITALS_COLUMNS = (%w[at] + DeviceVital::REPORTED - %w[reported_at services]).freeze
  # Unit names come off a remote box, so they're truncated before they become JSON keys.
  SERVICE_NAME_LIMIT = 40

  def detections
    return head :not_found if ingest_token.blank?
    return head :unauthorized unless authorized?

    rows = permitted_rows
    if rows.any?
      store_batch(rows)
      scan_alerts(rows)
      prepare_species_content(rows)
      generate_illustrations(rows)
      refresh_summary
    end
    render json: { upserted: rows.size }
  end

  # The liveness half of the push: the same ticks the listener writes, so the cloud can
  # tell a quiet spell from a stalled feed (AdminHealth) and ghost blind spots in the
  # sparkline. No alerts/summary — a tick isn't news.
  def heartbeats
    return head :not_found if ingest_token.blank?
    return head :unauthorized unless authorized?

    rows = permitted_heartbeats
    if rows.any?
      store_heartbeats(rows)
      Heartbeat.where(at: ...HEARTBEAT_RETENTION.ago).delete_all
    end
    render json: { upserted: rows.size }
  end

  # The third thing the push carries, and the only one that isn't a stream: the device's current
  # vital signs (see DeviceVital). No dedupe_key and no cursor — there is nothing to replay,
  # because a snapshot that didn't arrive is simply superseded by the next one. A missing or
  # empty payload is a 200 with nothing stored: the device deliberately sends nothing when its
  # collectors all failed, and that is not an error the push should have to handle.
  def vitals
    return head :not_found if ingest_token.blank?
    return head :unauthorized unless authorized?

    report = permitted_vitals
    DeviceVital.record!(report) if report.present?
    render json: { stored: report.present? }
  end

  private

  # Turn this batch's species into alert events + emails. Rescued: the mirror copy
  # is already saved, so a hiccup in alerting must never fail the ingest.
  def scan_alerts(rows)
    AlertEngine.scan(rows.pluck('Sci_Name'))
  rescue StandardError => e
    Rails.logger.error("[alerts] scan failed: #{e.class} #{e.message}")
  end

  # Queue up the modal content for any species in this batch that hasn't got it yet, so the
  # page is built before anyone asks for it rather than during their click. Enqueue only —
  # the work is two model calls and must never sit in the Pi's push request. Rescued for the
  # same reason as alerts: the mirror copy is saved, and a queueing hiccup must not fail the
  # ingest. If it does fail, the modal simply falls back to fetching on the click as before.
  def prepare_species_content(rows)
    SpeciesInfo.missing_content(rows.pluck('Sci_Name')).each do |sci|
      PrepareSpeciesContentJob.perform_later(sci)
    end
  rescue StandardError => e
    Rails.logger.error("[species] content enqueue failed: #{e.class} #{e.message}")
  end

  # Render the illustration for any bird in this batch we can't yet picture, so a newly-arrived
  # species stops showing a blank on the collage — generated in the cloud and published to the
  # CDN, no desktop run. Enqueue only (the render is a Gemini call + image work, for the worker);
  # the job re-checks the bucket so a bird already rendered is skipped. No-ops until the bucket is
  # configured. Rescued like the others: the mirror copy is saved, a queueing hiccup must not fail
  # the ingest.
  def generate_illustrations(rows)
    return unless Illustrations.enabled?

    rows.pluck('Sci_Name', 'Com_Name').uniq(&:first).each do |sci, com|
      next if BirdMask.for(Illustrations.slug(sci)) # already have art for this bird

      GenerateIllustrationJob.perform_later(sci, com)
    end
  rescue StandardError => e
    Rails.logger.error("[illustration] enqueue failed: #{e.class} #{e.message}")
  end

  # Regenerate the LLM "today" summary now that fresh data has landed (staleness-
  # guarded to ~one Bedrock call per window). Rescued for the same reason as alerts.
  def refresh_summary
    TodaySummary.refresh_if_stale
  rescue StandardError => e
    Rails.logger.error("[summary] refresh failed: #{e.class} #{e.message}")
  end

  # Bulk idempotent upsert keyed on dedupe_key. Skipping validations is the point —
  # the Pi is the validated source of truth; this is a mirror copy. SQLite needs an
  # explicit conflict target (unique_by:); MySQL/trilogy's ON DUPLICATE KEY UPDATE
  # fires off any unique index (the dedupe_key one) and rejects :unique_by outright.
  def store_batch(rows)
    if Detection.connection.adapter_name.match?(/mysql|trilogy/i)
      Detection.upsert_all(rows) # rubocop:disable Rails/SkipsModelValidations
    else
      Detection.upsert_all(rows, unique_by: :dedupe_key) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  # Same idempotent-upsert shape as detections, keyed on the heartbeat dedupe_key.
  def store_heartbeats(rows)
    if Heartbeat.connection.adapter_name.match?(/mysql|trilogy/i)
      Heartbeat.upsert_all(rows) # rubocop:disable Rails/SkipsModelValidations
    else
      Heartbeat.upsert_all(rows, unique_by: :dedupe_key) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def permitted_heartbeats
    params.permit(heartbeats: HEARTBEAT_COLUMNS).fetch(:heartbeats, []).
      map(&:to_h).select { |row| row['dedupe_key'].present? }
  end

  def ingest_token
    ENV.fetch('CLOUD_INGEST_TOKEN', nil)
  end

  # Constant-time bearer-token check.
  def authorized?
    provided = request.headers['Authorization'].to_s.sub(/\ABearer\s+/i, '')
    provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, ingest_token)
  end

  # The vitals payload, narrowed to what a device is allowed to say about itself. The scalar
  # fields map straight onto columns; `at` is renamed to reported_at so the device's clock and
  # ours are never confusable once stored.
  #
  # `services` is permitted by hand rather than through strong params, because its keys are the
  # unit names — open-ended by design, so adding a watched service is a device-side change — and
  # permit() can only whitelist keys it knows. Each unit is rebuilt from scratch into
  # {state, restarts} so an old or tampered-with payload can't smuggle arbitrary JSON into the
  # column; anything unrecognised is dropped, not stored.
  def permitted_vitals
    fields = params.permit(vitals: VITALS_COLUMNS).fetch(:vitals, {}).to_h
    return {} if fields.blank?

    report = fields.except('at').merge('reported_at' => fields['at'])
    report.merge('services' => permitted_services).compact
  end

  def permitted_services
    units = params.dig(:vitals, :services)
    return nil unless units.respond_to?(:each_pair)

    units.to_unsafe_h.filter_map do |name, unit|
      next unless unit.respond_to?(:[])

      [name.to_s.first(SERVICE_NAME_LIMIT), { 'state'    => unit['state'].to_s.presence,
                                              'restarts' => unit['restarts']&.to_i }]
    end.to_h.presence
  end

  # Strong params: an array of detection hashes, each limited to known columns,
  # and every row must carry a dedupe_key (the upsert conflict target).
  def permitted_rows
    params.permit(detections: UPSERT_COLUMNS).fetch(:detections, []).
      map(&:to_h).select { |row| row['dedupe_key'].present? }
  end
end
