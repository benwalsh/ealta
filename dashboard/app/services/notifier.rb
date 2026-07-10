# Sends alert emails via SES. Both the immediate single-bird alert and the daily
# digest are built here as SES *simple* content — the HTML/text live in Ruby, not in
# a SES-stored template (nothing about the email lives in Terraform). Images are plain
# URLs to the CloudFront-hosted illustrations, not attachments.
#
# Disabled unless ALERTS_FROM is set, so dev, test, and the Pi never try to send.
# Returns true on success (or when disabled) and false on failure — the caller
# leaves the event unsent on false so the next ingest tick retries.
class Notifier
  # Why this bird is worth an email — one line per alert kind, in the house voice.
  # REASON is the body's lead sentence; HEADLINE is the subject.
  REASON = {
    'rarity'     => 'A locally scarce bird — heard on only a handful of days.',
    'seasonal'   => 'Back for the season, after a spell away.',
    'first_ever' => 'The first time the station has ever heard this one.',
    'species'    => 'One of the birds you follow.'
  }.freeze
  HEADLINE = {
    'rarity'     => ->(name) { "A local rarity: #{name}" },
    'seasonal'   => ->(name) { "#{name} — back for the season" },
    'first_ever' => ->(name) { "First ever at the station: #{name}" },
    'species'    => ->(name) { "#{name} — a bird you follow" }
  }.freeze

  class << self
    def deliver(event:, subscription:)
      return true unless enabled?

      name = BirdName.lookup(event.sci_name)
      client.send_email(
        from_email_address: ENV.fetch('ALERTS_FROM'),
        destination:        { to_addresses: [subscription.email] },
        content:            { simple: {
          subject: { data: headline(event.event_type, name.en) },
          body:    { html: { data: alert_html(event, subscription, name) },
                     text: { data: alert_text(event, subscription, name) } }
        } }
      )
      true
    rescue StandardError => e
      Rails.logger.warn("[alerts] send failed for #{subscription.email}: #{e.class} #{e.message}")
      false
    end

    # One digest email — a DigestFacts object, narrated by DigestSummary (with the
    # mechanical list as fallback). SES *simple* content, not a template, since it's
    # variable and part LLM-written. Same fail-soft contract as deliver.
    def deliver_digest(user:, date:, facts:)
      return true unless enabled?

      # Prefer the enrichment-aware assembly (Nova over the day's cited blocks); fall
      # back to the plain summary, then to the mechanical list — warmth degrades, the
      # send never does.
      note = Enrichment::Assembler.for(user: user, date: date) || DigestSummary.for(facts)
      client.send_email(
        from_email_address: ENV.fetch('ALERTS_FROM'),
        destination:        { to_addresses: [user.email] },
        content:            { simple: {
          subject: { data: "Your station birds — #{I18n.l(date, format: :long)}" },
          body:    { html: { data: digest_html(facts, date, note) }, text: { data: digest_text(facts, date, note) } }
        } }
      )
      true
    rescue StandardError => e
      Rails.logger.warn("[digest] send failed for #{user.email}: #{e.class} #{e.message}")
      false
    end

    def enabled?
      ENV['ALERTS_FROM'].present?
    end

    private

    def client
      @client ||= Aws::SESV2::Client.new
    end

    # Display rows: the followed birds heard (with counts), then the flagged arrivals.
    def digest_rows(facts)
      follows = facts.follows.map { |f| { en: f[:en], ga: f[:ga], note: "heard #{f[:count]}×" } }
      alerts  = facts.alerts.map { |a| { en: a[:en], ga: a[:ga], note: REASON.fetch(a[:kind], '') } }
      follows + alerts
    end

    def digest_html(facts, date, note)
      prose = Array(note).map do |para|
        %(<p style="font-size:16px;line-height:1.55;margin:0 0 12px;">#{h(para)}</p>)
      end.join
      rows = digest_rows(facts).map do |row|
        <<-ROW
          <tr><td style="padding:11px 0;border-bottom:1px solid #e4e4e7;">
            <span style="font-size:17px;color:#17171a;">#{h(row[:en])}</span>
            <span style="font-size:14px;color:#8b8b91;font-style:italic;">&nbsp;#{h(row[:ga])}</span>
            <span style="font-size:13px;color:#8b8b91;float:right;">#{h(row[:note])}</span>
          </td></tr>
        ROW
      end.join
      day = if facts.roundup
              "#{facts.roundup[:species_today]} species, #{facts.roundup[:detections_today]} detections"
            end
      <<-HTML
        <div style="margin:0;padding:24px;background:#f2f2f3;font-family:Georgia,'Times New Roman',serif;color:#17171a;">
          <div style="max-width:520px;margin:0 auto;background:#fff;border:1px solid #e4e4e7;border-radius:10px;padding:24px 28px;">
            <div style="font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#8b8b91;">#{h(Station.site_name)} · #{h(I18n.l(date, format: :long))}</div>
            <div style="font-size:24px;margin:6px 0 14px;">The day's birds</div>
            #{prose}
            #{%(<table style="width:100%;border-collapse:collapse;margin-top:6px;">#{rows}</table>) unless rows.empty?}
            #{%(<div style="font-size:13px;color:#8b8b91;margin-top:14px;">#{h(day)} logged today.</div>) if day}
            <a href="#{site_url}" style="display:inline-block;margin-top:20px;background:#17171a;color:#fff;text-decoration:none;font-family:Helvetica,Arial,sans-serif;font-size:14px;padding:11px 20px;border-radius:6px;">See the collage</a>
            <div style="margin-top:16px;font-family:Helvetica,Arial,sans-serif;font-size:12px;color:#8b8b91;">Manage how you're told at <a href="#{site_url}/account" style="color:#8b8b91;">your account</a>.</div>
          </div>
        </div>
      HTML
    end

    def digest_text(facts, date, note)
      prose = Array(note).join("\n\n")
      rows = digest_rows(facts).map { |row| "- #{row[:en]} (#{row[:ga]}) — #{row[:note]}" }.join("\n")
      body = [prose.presence, rows.presence].compact.join("\n\n")
      "The day's birds — #{I18n.l(date, format: :long)}\n\n#{body}\n\n" \
        "See the collage: #{site_url}\nManage: #{site_url}/account"
    end

    def h(text)
      ERB::Util.html_escape(text)
    end

    def headline(kind, name_en)
      (HEADLINE[kind] || ->(name) { "#{name} heard at the station" }).call(name_en)
    end

    # The single-bird alert email — one illustrated card, on-palette with the site.
    def alert_html(event, subscription, name)
      slug = event.sci_name.downcase.tr(' ', '-')
      reason = REASON.fetch(event.event_type, 'Heard at the station.')
      date = I18n.l(event.occurred_on, format: :long)
      <<-HTML
        <div style="margin:0;padding:24px;background:#f2f2f3;font-family:Georgia,'Times New Roman',serif;color:#17171a;">
          <div style="max-width:520px;margin:0 auto;background:#fff;border:1px solid #e4e4e7;border-radius:10px;overflow:hidden;">
            <img src="#{site_url}/birds/#{slug}.png" alt="#{h(name.en)}" width="520" style="display:block;width:100%;height:auto;background:#f2f2f3;">
            <div style="padding:24px 28px;">
              <div style="font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#8b8b91;margin-bottom:10px;">Heard at the station</div>
              <div style="font-size:26px;line-height:1.15;">#{h(name.en)}</div>
              <div style="font-size:18px;color:#3d3d42;margin-top:2px;">#{h(name.ga)}</div>
              <div style="font-size:14px;font-style:italic;color:#8b8b91;margin-top:6px;">#{h(event.sci_name)}</div>
              <p style="font-size:15px;color:#3d3d42;line-height:1.55;margin:18px 0 22px;">
                <strong>#{h(reason)}</strong> The listening station picked it up on #{h(date)}.
              </p>
              <a href="#{site_url}" style="display:inline-block;background:#17171a;color:#fff;text-decoration:none;font-family:Helvetica,Arial,sans-serif;font-size:14px;padding:11px 20px;border-radius:6px;">See the collage</a>
            </div>
            <div style="padding:16px 28px;border-top:1px solid #e4e4e7;font-family:Helvetica,Arial,sans-serif;font-size:12px;color:#8b8b91;">
              You asked to hear about this. <a href="#{unsubscribe_url(subscription)}" style="color:#8b8b91;">Unsubscribe</a>.
            </div>
          </div>
        </div>
      HTML
    end

    def alert_text(event, subscription, name)
      reason = REASON.fetch(event.event_type, 'Heard at the station.')
      "#{name.en} (#{name.ga}) — #{event.sci_name}\n" \
        "#{reason} Heard at the station on #{I18n.l(event.occurred_on, format: :long)}.\n\n" \
        "See the collage: #{site_url}\nUnsubscribe: #{unsubscribe_url(subscription)}"
    end

    def unsubscribe_url(subscription)
      "#{site_url}/subscriptions/#{subscription.token}/unsubscribe"
    end

    def site_url
      ENV.fetch('SITE_URL', 'http://localhost:4030')
    end
  end
end
