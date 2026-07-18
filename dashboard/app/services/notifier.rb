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
      dispatch(
        recipient:   subscription.email,
        subject:     headline(event.event_type, name.en),
        html:        alert_html(event, subscription, name),
        text:        alert_text(event, subscription, name),
        unsubscribe: unsubscribe_url(subscription)
      )
    rescue StandardError => e
      Rails.logger.warn("[alerts] send failed for #{subscription.email}: #{e.class} #{e.message}")
      false
    end

    # The Daily Letter — the completed day's frozen Journal entry, verbatim: the letter
    # and the Journal page are the same words. SES *simple* content, same fail-soft
    # contract as deliver.
    def deliver_letter(user:, date:, entry:, hero: nil)
      return true unless enabled?

      unsub = letter_unsubscribe_url(user)
      dispatch(
        recipient:   user.email,
        subject:     "#{Station.site_name} — #{I18n.l(date, format: :long)}",
        html:        letter_html(entry, date, hero, unsub),
        text:        letter_text(entry, date, hero, unsub),
        unsubscribe: unsub
      )
    rescue StandardError => e
      Rails.logger.warn("[letter] send failed for #{user.email}: #{e.class} #{e.message}")
      false
    end

    def enabled?
      ENV['ALERTS_FROM'].present?
    end

    # The letter's HTML rendered but NOT sent — the admin preview. The same words a
    # subscriber would receive; no unsubscribe link, because nothing was delivered.
    def letter_preview(date:, entry:, hero: nil)
      letter_html(entry, date, hero, nil)
    end

    # A one-off note to the letter's readers — the rare "the station is off for a fortnight"
    # message, not part of the daily rhythm. Same envelope as the letter, deliberately: it goes
    # through dispatch, so a suppressed address is skipped and the RFC 8058 one-click
    # unsubscribe rides along. The unsubscribe is the LETTER's, because these are the letter's
    # readers — opting out of one is opting out of the station's email, which is the honest
    # reading of the tick they gave us.
    def deliver_blast(user:, subject:, body:)
      return true unless enabled?

      unsub = letter_unsubscribe_url(user)
      dispatch(recipient: user.email, subject: subject,
               html: blast_html(subject, body, unsub), text: blast_text(subject, body, unsub),
               unsubscribe: unsub)
    rescue StandardError => e
      Rails.logger.warn("[blast] send failed for #{user.email}: #{e.class} #{e.message}")
      false
    end

    # What the blast will look like, rendered but not sent — so nobody mails a few hundred
    # readers without having read it themselves first.
    def blast_preview(subject:, body:)
      blast_html(subject, body, nil)
    end

    private

    # The one SES send. Skips a suppressed address (returning true, so the caller
    # treats it as handled and doesn't retry); attaches the RFC 8058 one-click
    # unsubscribe headers every message must carry; and routes through the
    # configuration set that feeds bounce/complaint events back to us. Raises on a
    # real API failure so the caller can leave the event unsent and retry.
    def dispatch(recipient:, subject:, html:, text:, unsubscribe:)
      return true if EmailSuppression.suppressed?(recipient)

      params = {
        from_email_address: ENV.fetch('ALERTS_FROM'),
        destination:        { to_addresses: [recipient] },
        content:            { simple: {
          subject: { data: subject },
          body:    { html: { data: html }, text: { data: text } },
          headers: [
            { name: 'List-Unsubscribe',      value: "<#{unsubscribe}>" },
            { name: 'List-Unsubscribe-Post', value: 'List-Unsubscribe=One-Click' }
          ]
        } }
      }
      params[:configuration_set_name] = config_set if config_set
      client.send_email(**params)
      true
    end

    # The SES configuration set that fans delivery events to SNS. Unset in dev/test and
    # on the Pi — then we send plain, exactly as before.
    def config_set
      ENV['SES_CONFIGURATION_SET'].presence
    end

    def client
      @client ||= Aws::SESV2::Client.new
    end

    # The letter's paragraphs: the journal bullets in the station's own language, with
    # the second language beneath when the station is bilingual (Irish-first stations
    # lead with Irish, exactly like the Journal page).
    def letter_bullets(entry)
      # A thin 'template' day (an empty day, quiet or offline) has no narration worth sending — give
      # it one honest coverage-aware line instead of the bare "0 species…" template.
      bullets = entry.source == 'template' ? empty_day_bullets(entry) : entry.bullets.deep_symbolize_keys
      primary = Array(bullets[Station.default_language]).presence || Array(bullets[:en])
      second = Station.multilingual? ? Station.languages[1] : nil
      secondary = second ? Array(bullets[second]).presence : nil
      secondary = nil if secondary == primary
      [primary, secondary]
    end

    # The line for an empty (zero-detection) day. We can't tell a genuinely quiet day from a mic that
    # was down, so we state how long it actually listened rather than assert silence: "offline for
    # most of the day — recorded N of 24 hours" vs "listened N of 24 and logged nothing". Plain lines
    # when coverage is unknown (an old day past heartbeat retention), where no listening time is known.
    def empty_day_bullets(entry)
      coverage = Array(entry.coverage)
      return unknown_day_bullets if coverage.blank?

      hours = coverage.count { |up| up }
      if hours < coverage.size / 2
        { en: ["The station was offline for most of the day — the mic recorded #{hours} of 24 hours."],
          ga: ["Bhí an stáisiún as líne formhór an lae — níor thaifead an micreafón ach #{hours}/24 uair."] }
      else
        { en: ["A quiet day at the station — the mic listened #{hours} of 24 hours and logged nothing."],
          ga: ["Lá ciúin ag an stáisiún — d'éist an micreafón #{hours}/24 uair agus níor thaifead sé faic."] }
      end
    end

    def unknown_day_bullets
      { en: ['A quiet day at the station — little was heard.'],
        ga: ['Lá ciúin ag an stáisiún — is beag a chualathas.'] }
    end

    def letter_html(entry, date, hero = nil, unsubscribe = nil)
      primary, secondary = letter_bullets(entry)
      banner = hero_banner(hero)
      paras = primary.map do |b|
        %(<p style="font-size:16px;line-height:1.55;margin:0 0 12px;">#{h(b)}</p>)
      end.join
      gloss = Array(secondary).map do |b|
        %(<p style="font-size:14px;line-height:1.5;margin:0 0 10px;color:#8b8b91;font-style:italic;">#{h(b)}</p>)
      end.join
      # A short deep dive on the day's hero — its already-sourced Wikipedia summary, the extra
      # texture the newsletter has room for that the panel doesn't.
      dive = deep_dive_html(hero)
      hosts = entry.sources.filter_map { |src| src['host'] }
      hosts << 'en.wikipedia.org' if dive.present?
      sources = hosts.uniq.join(' · ')
      # The keeper's own line for the day, set apart from the narration rather than woven into
      # it — the same note the journal page shows, so the two never diverge. One indexed lookup
      # by date; cheap enough not to thread through every caller.
      note = DayNote.body_for(date)
      <<-HTML
        <div style="margin:0;padding:24px;background:#f2f2f3;font-family:Georgia,'Times New Roman',serif;color:#17171a;">
          <div style="max-width:520px;margin:0 auto;background:#fff;border:1px solid #e4e4e7;border-radius:10px;overflow:hidden;">
            #{banner}
            <div style="padding:24px 28px;">
            <div style="font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#8b8b91;">#{h(Station.site_name)} · #{h(I18n.l(date, format: :long))}</div>
            #{%(<div style="font-size:13px;color:#8b8b91;margin-top:4px;">#{h([hero[:en], hero[:ga]].compact.join(' · '))}</div>) if hero}
            <div style="font-size:24px;margin:6px 0 14px;">The day's journal</div>
            #{%(<div style="border-left:3px solid #17171a;padding:2px 0 2px 14px;margin:0 0 16px;"><div style="font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:#8b8b91;margin-bottom:5px;">A note from the station</div><div style="font-size:15px;line-height:1.55;">#{h(note).gsub("\n", '<br>')}</div></div>) if note}
            #{paras}
            #{%(<div style="border-top:1px solid #e4e4e7;margin:14px 0;padding-top:12px;">#{gloss}</div>) if gloss.present?}
            #{dive}
            #{%(<div style="font-size:12px;color:#8b8b91;margin-top:10px;">Sources: #{h(sources)}</div>) if sources.present?}
            <a href="#{site_url}" style="display:inline-block;margin-top:20px;background:#17171a;color:#fff;text-decoration:none;font-family:Helvetica,Arial,sans-serif;font-size:14px;padding:11px 20px;border-radius:6px;">Read the journal</a>
            <div style="margin-top:16px;font-family:Helvetica,Arial,sans-serif;font-size:12px;color:#8b8b91;">Manage your letter at <a href="#{site_url}/account" style="color:#8b8b91;">your account</a>#{%(, or <a href="#{h(unsubscribe)}" style="color:#8b8b91;">unsubscribe in one click</a>) if unsubscribe}.</div>
            </div>
          </div>
        </div>
      HTML
    end

    # The blast wears the letter's envelope — same paper card, same footer — so a note from
    # the station looks like it came from the station. The body is plain text the keeper typed:
    # blank lines part paragraphs, and nothing else is interpreted.
    def blast_html(subject, body, unsubscribe = nil)
      paras = body.to_s.split(/\n{2,}/).map do |para|
        %(<p style="font-size:16px;line-height:1.55;margin:0 0 12px;">#{h(para.strip).gsub("\n", '<br>')}</p>)
      end.join
      <<-HTML
        <div style="margin:0;padding:24px;background:#f2f2f3;font-family:Georgia,'Times New Roman',serif;color:#17171a;">
          <div style="max-width:520px;margin:0 auto;background:#fff;border:1px solid #e4e4e7;border-radius:10px;overflow:hidden;">
            <div style="padding:24px 28px;">
            <div style="font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#8b8b91;">#{h(Station.site_name)}</div>
            <div style="font-size:24px;margin:6px 0 14px;">#{h(subject)}</div>
            #{paras}
            <a href="#{site_url}" style="display:inline-block;margin-top:20px;background:#17171a;color:#fff;text-decoration:none;font-family:Helvetica,Arial,sans-serif;font-size:14px;padding:11px 20px;border-radius:6px;">Visit the station</a>
            <div style="margin-top:16px;font-family:Helvetica,Arial,sans-serif;font-size:12px;color:#8b8b91;">Manage your letter at <a href="#{site_url}/account" style="color:#8b8b91;">your account</a>#{%(, or <a href="#{h(unsubscribe)}" style="color:#8b8b91;">unsubscribe in one click</a>) if unsubscribe}.</div>
            </div>
          </div>
        </div>
      HTML
    end

    def blast_text(subject, body, unsubscribe = nil)
      "#{subject}\n\n#{body}\n\nVisit the station: #{site_url}\nManage: #{site_url}/account" \
        "#{"\nUnsubscribe: #{unsubscribe}" if unsubscribe}"
    end

    def letter_text(entry, date, hero = nil, unsubscribe = nil)
      primary, secondary = letter_bullets(entry)
      body = [primary.join("\n\n"), Array(secondary).join("\n\n").presence].compact.join("\n\n---\n\n")
      body = "The day's bird: #{[hero[:en], hero[:ga]].compact.join(' · ')}\n\n#{body}" if hero
      note = DayNote.body_for(date)
      body = "A note from the station:\n\n#{note}\n\n#{body}" if note
      dive, = hero_description(hero)
      body = "#{body}\n\nAbout the #{hero[:en]}: #{dive}" if dive.present?
      sources = entry.sources.filter_map { |src| src['host'] }.uniq.join(', ')
      "The day's journal — #{I18n.l(date, format: :long)}\n\n#{body}\n\n" \
        "#{"Sources: #{sources}\n" if sources.present?}Read the journal: #{site_url}\nManage: #{site_url}/account" \
        "#{"\nUnsubscribe: #{unsubscribe}" if unsubscribe}"
    end

    # The day's hero, full-bleed at the top. The newsletter has room the panel doesn't, so it
    # prefers a real Wikimedia Commons PHOTO (credited — CC images must be attributed); failing that,
    # the station's dithered illustration (the same /birds art the site shows); failing both, no
    # banner and the letter leads with the caption + prose.
    def hero_banner(hero)
      return '' unless hero

      caption = [hero[:en], hero[:ga]].compact.join(' · ')
      photo = SpeciesInfo.photo_for(hero[:sci])
      return photo_banner(photo, caption) if photo
      return illustration_banner(hero[:slug], caption) if hero[:slug]

      ''
    end

    def photo_banner(photo, caption)
      img = %(<img src="#{h(photo[:url])}" alt="#{h(caption)}" width="520" ) +
            %(style="display:block;width:100%;height:auto;background:#f2f2f3;">)
      return img if photo[:credit].blank?

      credit = 'font-size:11px;color:#8b8b91;padding:6px 28px 0;font-family:Helvetica,Arial,sans-serif'
      "#{img}<div style=\"#{credit}\">#{h(photo[:credit])}</div>"
    end

    def illustration_banner(slug, caption)
      %(<img src="#{site_url}/birds/#{slug}.png" alt="#{h(caption)}" width="520" ) +
        %(style="display:block;width:100%;height:auto;background:#f2f2f3;">)
    end

    # The hero's "About the …" block — its already-sourced Wikipedia summary, primary language then
    # a muted gloss for a bilingual station. '' when there's no hero or no summary yet.
    def deep_dive_html(hero)
      primary, secondary = hero_description(hero)
      return '' if primary.blank?

      heading = "About the #{[hero[:en], hero[:ga]].compact.join(' · ')}"
      paras = %(<p style="font-size:15px;line-height:1.6;margin:0 0 8px;">#{h(primary)}</p>)
      if secondary.present?
        gloss = 'font-size:13px;line-height:1.5;margin:0;color:#8b8b91;font-style:italic'
        paras += %(<p style="#{gloss}">#{h(secondary)}</p>)
      end
      label = 'font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#8b8b91;margin-bottom:8px'
      %(<div style="border-top:1px solid #e4e4e7;margin:16px 0 0;padding-top:14px;">) +
        %(<div style="#{label}">#{h(heading)}</div>#{paras}</div>)
    end

    # [primary, secondary] descriptions for the hero, in the station's language order (Irish-first
    # stations lead with Irish). nil hero → [nil, nil].
    def hero_description(hero)
      return [nil, nil] unless hero

      card = HeroCard.for(hero[:sci])
      by_lang = { en: card[:description], ga: card[:description_ga].presence }
      primary = by_lang[Station.default_language] || card[:description]
      second = Station.multilingual? ? Station.languages[1] : nil
      secondary = second ? by_lang[second] : nil
      secondary = nil if secondary.blank? || secondary == primary
      [primary, secondary]
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

    # The daily letter's one-click unsubscribe is per-user, not per-subscription: it
    # covers the roundup opt-in and any follow that was riding the digest together.
    def letter_unsubscribe_url(user)
      "#{site_url}/letter/#{user.letter_token}/unsubscribe"
    end

    def site_url
      ENV.fetch('SITE_URL', 'http://localhost:4030')
    end
  end
end
