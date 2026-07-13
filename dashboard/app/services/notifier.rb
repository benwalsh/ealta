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

    # The Daily Letter — the completed day's frozen Journal entry, verbatim: the letter
    # and the Journal page are the same words. SES *simple* content, same fail-soft
    # contract as deliver.
    def deliver_letter(user:, date:, entry:, hero: nil)
      return true unless enabled?

      client.send_email(
        from_email_address: ENV.fetch('ALERTS_FROM'),
        destination:        { to_addresses: [user.email] },
        content:            { simple: {
          subject: { data: "#{Station.site_name} — #{I18n.l(date, format: :long)}" },
          body:    { html: { data: letter_html(entry, date, hero) },
                     text: { data: letter_text(entry, date, hero) } }
        } }
      )
      true
    rescue StandardError => e
      Rails.logger.warn("[letter] send failed for #{user.email}: #{e.class} #{e.message}")
      false
    end

    def enabled?
      ENV['ALERTS_FROM'].present?
    end

    private

    def client
      @client ||= Aws::SESV2::Client.new
    end

    # The letter's paragraphs: the journal bullets in the station's own language, with
    # the second language beneath when the station is bilingual (Irish-first stations
    # lead with Irish, exactly like the Journal page).
    def letter_bullets(entry)
      bullets = entry.bullets.deep_symbolize_keys
      primary = Array(bullets[Station.default_language]).presence || Array(bullets[:en])
      second = Station.multilingual? ? Station.languages[1] : nil
      secondary = second ? Array(bullets[second]).presence : nil
      secondary = nil if secondary == primary
      [primary, secondary]
    end

    def letter_html(entry, date, hero = nil)
      primary, secondary = letter_bullets(entry)
      # The day's most notable bird, full-bleed at the top — the same illustration the
      # site shows (/birds redirects to the CDN when the art lives there).
      banner = if hero
                 caption = [hero[:en], hero[:ga]].compact.join(' · ')
                 %(<img src="#{site_url}/birds/#{hero[:slug]}.png" alt="#{h(caption)}" width="520"
                        style="display:block;width:100%;height:auto;background:#f2f2f3;">)
               end
      paras = primary.map do |b|
        %(<p style="font-size:16px;line-height:1.55;margin:0 0 12px;">#{h(b)}</p>)
      end.join
      gloss = Array(secondary).map do |b|
        %(<p style="font-size:14px;line-height:1.5;margin:0 0 10px;color:#8b8b91;font-style:italic;">#{h(b)}</p>)
      end.join
      sources = entry.sources.filter_map { |src| src['host'] }.uniq.join(' · ')
      <<-HTML
        <div style="margin:0;padding:24px;background:#f2f2f3;font-family:Georgia,'Times New Roman',serif;color:#17171a;">
          <div style="max-width:520px;margin:0 auto;background:#fff;border:1px solid #e4e4e7;border-radius:10px;overflow:hidden;">
            #{banner}
            <div style="padding:24px 28px;">
            <div style="font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#8b8b91;">#{h(Station.site_name)} · #{h(I18n.l(date, format: :long))}</div>
            #{%(<div style="font-size:13px;color:#8b8b91;margin-top:4px;">#{h([hero[:en], hero[:ga]].compact.join(' · '))}</div>) if hero}
            <div style="font-size:24px;margin:6px 0 14px;">The day's journal</div>
            #{paras}
            #{%(<div style="border-top:1px solid #e4e4e7;margin:14px 0;padding-top:12px;">#{gloss}</div>) if gloss.present?}
            #{%(<div style="font-size:12px;color:#8b8b91;margin-top:10px;">Sources: #{h(sources)}</div>) if sources.present?}
            <a href="#{site_url}" style="display:inline-block;margin-top:20px;background:#17171a;color:#fff;text-decoration:none;font-family:Helvetica,Arial,sans-serif;font-size:14px;padding:11px 20px;border-radius:6px;">Read the journal</a>
            <div style="margin-top:16px;font-family:Helvetica,Arial,sans-serif;font-size:12px;color:#8b8b91;">Manage your letter at <a href="#{site_url}/account" style="color:#8b8b91;">your account</a>.</div>
            </div>
          </div>
        </div>
      HTML
    end

    def letter_text(entry, date, hero = nil)
      primary, secondary = letter_bullets(entry)
      body = [primary.join("\n\n"), Array(secondary).join("\n\n").presence].compact.join("\n\n---\n\n")
      body = "The day's bird: #{[hero[:en], hero[:ga]].compact.join(' · ')}\n\n#{body}" if hero
      sources = entry.sources.filter_map { |src| src['host'] }.uniq.join(', ')
      "The day's journal — #{I18n.l(date, format: :long)}\n\n#{body}\n\n" \
        "#{"Sources: #{sources}\n" if sources.present?}Read the journal: #{site_url}\nManage: #{site_url}/account"
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
