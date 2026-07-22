require 'base64'
require 'json'

# A bird's 1-bit silhouette, read from masks.json (built by `make masks`). The
# collage packer uses these to nestle birds by their actual outline instead of
# bounding circles. Bits are MSB-first, row-major, 1 where the cutout is opaque.
class BirdMask
  class << self
    # The decoded mask for a slug, or nil if we have no silhouette for it.
    def for(slug)
      cache.fetch(slug) { cache[slug] = build(slug) }
    end

    # Every illustration slug the profile has a silhouette for (the keys of masks.json), including
    # the "-2" flight variants. masks.json is the small manifest that ships IN the app image, so
    # this is the one enumeration of the illustrated set that works everywhere — including the
    # cloud, where the PNGs themselves live only on the illustrations CDN, not the container's disk.
    def slugs
      table.keys
    end

    # Drop the memoized manifest — for specs that swap the active profile (and thus its art)
    # mid-run; in production the profile is fixed, so this is never called.
    def reset!
      @table = nil
      @cache = nil
    end

    private

    def build(slug)
      entry = table[slug]
      entry && new(entry['w'], entry['h'], Base64.decode64(entry['bits']))
    end

    # masks.json sits with the art it describes, in the station profile. A station with
    # no art has no masks, and the packer falls back to bounding circles.
    def table
      @table ||= begin
        path = StationProfile.path('illustrations/masks.json')
        path ? JSON.parse(path.read) : {}
      end
    end

    def cache
      @cache ||= {}
    end
  end

  attr_reader :width, :height

  def initialize(width, height, bytes)
    @width = width
    @height = height
    @bytes = bytes
  end

  # Is the silhouette opaque at normalised coordinates (u, v), each in [0, 1)?
  def opaque_at(unit_x, unit_y)
    mx = (unit_x * @width).floor.clamp(0, @width - 1)
    my = (unit_y * @height).floor.clamp(0, @height - 1)
    i = (my * @width) + mx
    byte = @bytes.getbyte(i >> 3) || 0
    byte.allbits?(1 << (7 - (i & 7)))
  end

  # The opaque cells as [mx, my] pairs — the sparse form the packer forward-maps
  # onto its occupancy grid (collision tests stay linear in opaque area).
  def cells
    @cells ||= begin
      list = []
      i = 0
      @height.times do |my|
        @width.times do |mx|
          byte = @bytes.getbyte(i >> 3) || 0
          list << [mx, my] if byte.allbits?(1 << (7 - (i & 7)))
          i += 1
        end
      end
      list
    end
  end
end
