# One outbound hit to a cultural/scientific source — the enrichment pipeline's
# politeness ledger. Written by Enrichment::Builder on every fetch so we can see,
# at a glance, that we hit dúchas once for the cuckoo, not fifty times.
class SourceFetchLog < ApplicationRecord
  validates :host, :fetched_at, presence: true
end
