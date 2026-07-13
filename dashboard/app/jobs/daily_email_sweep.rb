# The once-a-day cloud sweep, run on a recurring schedule by Solid Queue (see
# config/recurring.yml). Two halves, in order:
#   1. Enrichment::Builder.run — source the day's DUE enrichment (Claude), the
#      importance backoff deciding which birds are worth a fresh lookup.
#   2. DailyLetter.deliver_all — mail the frozen Journal entry to every letter
#      subscriber (SES).
# All idempotent: enrichment reuses still-fresh bundles rather than re-sourcing, the
# freeze is find-or-create, and DailyLetter skips any user already sent for the day
# (last_digest_on). So a retry — or a second run in the same day — is safe. Runs just
# after midnight station time (config/recurring.yml), so `yesterday` is the day that
# closed minutes ago.
class DailyEmailSweep < ApplicationJob
  queue_as :default

  def perform(date = Date.yesterday)
    date = Date.parse(date) if date.is_a?(String)
    Enrichment::Builder.run(date: date)
    freeze_journal(date)
    DailyLetter.deliver_all(date: date)
  end

  private

  # Freeze the completed day's Journal entry now that its lore is sourced — so the page reads
  # a frozen entry, not a build-on-view. Best-effort: a narration hiccup must not block the
  # digest, and build-on-view remains the backstop.
  def freeze_journal(date)
    JournalEntry.for(date)
  rescue StandardError => e
    Rails.logger.warn("DailyEmailSweep: journal freeze for #{date} failed (#{e.class}: #{e.message})")
  end
end
