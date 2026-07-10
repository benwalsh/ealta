# A liveness tick: the listener was capturing-and-analysing at this moment, even if it
# heard nothing. The presence of a tick means the mic → BirdNET loop was OPERATIVE then,
# so an absence of detections is a true zero — not missing data. Written by the Python
# listener every listening cycle (throttled); the app reads it to tell "quiet" from
# "stalled" (see AdminHealth) and, later, to draw the activity line honestly.
class Heartbeat < ApplicationRecord
  scope :since, ->(time) { where(at: time..) }

  class << self
    # The most recent tick, or nil if the listener has never checked in (pre-upgrade, or
    # the cloud mirror where ticks aren't synced yet).
    def last_at
      maximum(:at)
    end

    # Which of `count` consecutive buckets of `width` seconds from `start` the listener
    # was alive for — a boolean per bucket. A detection also proves liveness, so callers
    # OR this with "the bucket had a detection". Buckets with neither are missing data.
    def coverage(start, width, count)
      marks = Array.new(count, false)
      since(start).pluck(:at).each do |at|
        idx = ((at - start) / width).floor
        idx = count - 1 if idx == count
        marks[idx] = true if idx.between?(0, count - 1)
      end
      marks
    end
  end
end
