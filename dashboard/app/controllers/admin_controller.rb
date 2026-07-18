# Admin-only surface, never linked from the public chrome. Gated by User#admin?
# (ADMIN_EMAILS, fail-closed). Session-authed like /account; kept out of the
# cookie-free /api and out of the CloudFront cache (see cdn.tf).
class AdminController < ApplicationController
  before_action :require_admin

  BLAST_INCOMPLETE = 'A blast needs both a subject and something to say.'.freeze

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

  # Wipe the detection history — guarded by a typed confirmation (params[:confirm] == 'DELETE').
  def clear_data
    respond_admin(DataReset.clear!(confirm: params[:confirm]))
  end

  # Regenerate a completed day's frozen Journal entry — drop the frozen row and re-narrate it from
  # the day's current facts + enrichment. Dev/testing; runs the model inline, so it can take a
  # few seconds. Replies like every other admin action so the panel can show the result inline.
  def regenerate_journal
    date = Date.iso8601(params.require(:date))
    JournalEntry.where(date: date).destroy_all
    entry = JournalEntry.for(date)
    respond_admin({ ok:      entry.present?,
                    message: if entry
                               "Regenerated the journal for #{date}."
                             else
                               "No completed day at #{date} to regenerate."
                             end })
  rescue ActionController::ParameterMissing, ArgumentError
    respond_admin({ ok: false, message: 'Enter a valid date (YYYY-MM-DD) to regenerate.' })
  end

  # A day's letter rendered but not sent — the words a subscriber would get. Sending the real
  # letter is the scheduler's job (DailyEmailSweep); the console only ever previews it or sends
  # a copy to the admin, so nobody can mail every subscriber with a button press.
  def preview_letter
    date = Date.iso8601(params.require(:date))
    # find_by, NEVER JournalEntry.for: `for` is find-or-CREATE, so previewing a date would
    # write a journal row (and narrate it) as a side effect. A preview must only read.
    entry = JournalEntry.find_by(date: date)
    return render(plain: "No journal for #{date} yet — rebuild it first.", status: :not_found) unless entry

    html = Notifier.letter_preview(date: date, entry: entry, hero: DailyLetter.hero_bird(date))
    render html: html.html_safe, layout: false # rubocop:disable Rails/OutputSafety -- our own markup
  rescue ActionController::ParameterMissing, ArgumentError
    render plain: 'Enter a valid date (YYYY-MM-DD).', status: :bad_request
  end

  # Send that day's letter to the signed-in admin ALONE. Goes straight to Notifier rather than
  # through DailyLetter, so it never touches last_digest_on — a test send can't make the real
  # sweep skip you tomorrow.
  def send_test_letter
    date = Date.iso8601(params.require(:date))
    # find_by for the same reason as the preview: a test send must not fabricate the very
    # journal it is testing.
    entry = JournalEntry.find_by(date: date)
    return respond_admin({ ok: false, message: "No journal for #{date} to send — rebuild it first." }) unless entry
    return respond_admin({ ok: false, message: 'This station does not send email.' }) unless Notifier.enabled?

    sent = Notifier.deliver_letter(user: current_user, date: date, entry: entry,
                                   hero: DailyLetter.hero_bird(date))
    respond_admin({ ok:      sent,
                    message: sent ? "Sent the #{date} letter to #{current_user.email}." : 'Could not send.' })
  rescue ActionController::ParameterMissing, ArgumentError
    respond_admin({ ok: false, message: 'Enter a valid date (YYYY-MM-DD).' })
  end

  # What the blast will look like, rendered but not sent — returned as HTML for the console to
  # show inline, so the words can be read and reworked before anyone is mailed.
  def preview_blast
    subject, body = blast_params
    if subject.empty? || body.empty?
      return render(json:   { ok: false, message: BLAST_INCOMPLETE },
                    status: :unprocessable_content)
    end

    render json: { ok: true, html: Notifier.blast_preview(subject: subject, body: body) }
  end

  # A copy of the blast to the signed-in admin alone. The console requires this to have
  # succeeded before it will unlock the real send: nobody should mail the station's readers
  # something they have not seen land in their own inbox.
  def test_blast
    subject, body = blast_params
    return respond_admin({ ok: false, message: BLAST_INCOMPLETE }) if subject.empty? || body.empty?
    return respond_admin({ ok: false, message: 'This station does not send email.' }) unless Notifier.enabled?

    sent = Notifier.deliver_blast(user: current_user, subject: subject, body: body)
    respond_admin({ ok: sent, message: sent ? "Sent a copy to #{current_user.email}." : 'Could not send.' })
  end

  # The real send. `confirm` must be the recipient count typed out — not a word like SEND,
  # which is muscle memory, but the actual number of people about to be emailed, so the last
  # act before sending is reading how many. Checked here as well as in the console: the gate
  # has to hold for a crafted request too.
  def send_blast
    subject, body = blast_params
    expected = Blast.count
    return respond_admin({ ok: false, message: BLAST_INCOMPLETE }) if subject.empty? || body.empty?
    return respond_admin({ ok: false, message: 'This station does not send email.' }) unless Notifier.enabled?
    unless params[:confirm].to_s.strip == expected.to_s
      return respond_admin({ ok: false, message: "Type #{expected} to confirm sending to #{expected} readers." })
    end

    sent = Blast.deliver_all(subject: subject, body: body)
    respond_admin({ ok: true, message: "Sent to #{sent} #{'reader'.pluralize(sent)}." })
  end

  # The keeper's note for a day. GET reads it back so the box shows what is already there;
  # PUT writes it, and an empty box clears it. Stored apart from the journal entry, so
  # rebuilding a journal never takes the note with it and a note can be written for a day
  # whose entry the 00:15 sweep has not frozen yet.
  def day_note
    # No date means the day the NEXT letter covers — the one still in progress. A note is a
    # thing you say ahead ("the feeders are down tomorrow"), not a footnote added to a day
    # that has already gone, so the console doesn't ask you to pick one. The station's own
    # timezone decides which day that is, not the browser's.
    date = params[:date].present? ? Date.iso8601(params[:date]) : Time.current.to_date

    return render json: { date: date.iso8601, note: DayNote.body_for(date), sent: letter_sent?(date) } if request.get?

    body = DayNote.write(date: date, body: params[:note])
    respond_admin({ ok:      true,
                    message: if body
                               if letter_sent?(date)
                                 "Saved. The #{date} letter has already gone, " \
                                   'so this shows on the journal only.'
                               else
                                 "Saved the note for #{date}."
                               end
                             else
                               "Cleared the note for #{date}."
                             end })
  rescue ActionController::ParameterMissing, ArgumentError
    if request.get?
      render json: { error: 'Enter a valid date (YYYY-MM-DD).' }, status: :bad_request
    else
      respond_admin({ ok: false, message: 'Enter a valid date (YYYY-MM-DD).' })
    end
  end

  # Rebuild every species' modal content (the Wikipedia summary and its Irish translation).
  # Queued, not done inline: it is two model calls per bird across the whole life list, far
  # past a request. `refresh` clears the stored text first, which is how descriptions cached
  # while the model was unavailable — and frozen ever since — actually get replaced.
  #
  # This exists because there is no shell into the cloud: ECS Express Mode has no ECS Exec, so
  # `rails ealta:warm_species` can only be run locally, against the wrong database.
  def refresh_species_content
    force = params[:refresh].present?
    SpeciesContentSweepJob.perform_later(force: force)
    respond_admin({ ok:      true,
                    message: if force
                               'Rebuilding every species description in the background. ' \
                                 'They will turn over as the jobs run.'
                             else
                               'Filling in any missing species content in the background.'
                             end })
  end

  private

  # A blast needs both halves; an empty subject or body is never worth sending.
  def blast_params
    [params[:subject].to_s.strip, params[:body].to_s.strip]
  end

  # Has that day's letter already gone out? The sweep stamps each reader's last_digest_on, so
  # any reader stamped for the date means the words are already in inboxes — a note added now
  # can only reach the journal.
  def letter_sent?(date)
    User.exists?(last_digest_on: date)
  end

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
