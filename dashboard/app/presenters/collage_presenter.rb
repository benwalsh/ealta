require 'zlib'

# Turns a tally into a screen-ready collage: each bird an illustration sized by
# call count and nestled into a blob by its silhouette (MaskPacker), packed
# directly in the panel's pixel space. Names are NOT drawn on the birds — a single
# caption names the featured bird, and a tap swaps it
# (handled in JS). Pure presentation.
class CollagePresenter
  # Chromatic Spectra-6 inks, for species we don't yet ship art for (no-art
  # birds render as a plain coloured disc rather than a labelled chip).
  FILLS = ['#a53c38', '#31477e', '#3a6e48', '#c6b04a'].freeze

  # `image`/`flip` carry the collage's dressing (a flight pose for the fliers, a
  # daily left/right flip). `perch_image` is always the plain perched illustration —
  # the hits strip uses it so that distilled row stays calm and uniform.
  Node = Data.define(:cx, :cy, :r, :w, :h, :image, :perch_image, :fill, :sci, :ga, :en, :count, :flip)

  # Loudest bird's size vs the quietest. Kept low and applied on a log curve
  # (see scaled_radii) so frequency reads but a much-heard sparrow stays modestly
  # bigger rather than ginormous.
  SIZE_RATIO = 1.7
  # Fraction of species shown in their flight pose rather than perched (the rest
  # perch). FLY_PROB — flight is the occasional accent,
  # not the norm. Chosen deterministically per species (see flies?) so the e-ink
  # panel doesn't reshuffle poses between refreshes.
  FLY_PROB = 0.15
  # Safety clamp only — birds pack at their natural aspect so the mask maps 1:1.
  ASPECT_RANGE = (0.3..4.0)
  # Nominal px² per unit of (squared) size weight. Arbitrary — the cluster is
  # scaled to fill the panel afterwards, so this only sets the working resolution.
  NOMINAL_UNIT = 4000.0
  # Rough silhouette packing density, used only to size the (generous) work
  # canvas so nothing spills off it before the fit-to-region scale.
  PACK_FILL = 0.5
  # Default elliptical cluster — wider than tall, to match the landscape panel so
  # the fit-to-region scale fills both axes. Overridable per-instance (see
  # initialize) so a portrait surface (e.g. /station) can request a taller cluster
  # and still fill its frame with big birds.
  X_BIAS = 1.0
  Y_BIAS = 0.55
  # No-art birds pack as a filled square (a coarse all-on mask).
  NO_ART_DIM = 12
  NO_ART_CELLS = (0...NO_ART_DIM).flat_map { |y| (0...NO_ART_DIM).map { |x| [x, y] } }.freeze

  attr_reader :width, :height

  def initialize(tally, width: 800, height: 480, top_inset: 28, bottom_inset: 48, margin: 16,
                 x_bias: X_BIAS, y_bias: Y_BIAS)
    @tally = tally
    @width = width
    @height = height
    @top_inset = top_inset
    @bottom_inset = bottom_inset
    @margin = margin
    @x_bias = x_bias
    @y_bias = y_bias
  end

  def nodes
    @nodes ||= build_nodes
  end

  def species_count
    @tally.size
  end

  private

  def build_nodes
    return [] if @tally.empty?

    region_w = @width - (2 * @margin)
    region_h = @height - @top_inset - @bottom_inset
    birds = prepare_birds
    sizes = birds.map { |bird| nominal_size(bird) }
    positions = pack(birds, sizes)
    place(birds, sizes, positions, region_w, region_h)
  end

  def prepare_birds
    radii = scaled_radii
    flying = flying_set(@tally.map(&:sci_name))
    @tally.each_with_index.map do |tally, i|
      name = tally.name
      slug = illustration_slug(name.sci, flying.include?(name.sci))
      { tally: tally, name: name, slug: slug,
        mask: slug && BirdMask.for(slug),
        flip: facing_flip?(name.sci),
        weight: radii[i]**2, aspect: aspect_for(slug) }
    end
  end

  # Nominal [w, h] px: area ∝ size weight, at the bird's natural aspect.
  def nominal_size(bird)
    area = bird[:weight] * NOMINAL_UNIT
    [Math.sqrt(area * bird[:aspect]), Math.sqrt(area / bird[:aspect])]
  end

  # Nestle the silhouettes on a generous square canvas (sized so nothing spills),
  # returning a top-left per bird in canvas px.
  def pack(birds, sizes)
    span = Math.sqrt(sizes.sum { |w, h| w * h } / PACK_FILL)
    canvas = span * 2.0
    tiles = birds.each_with_index.map { |bird, i| tile_for(bird, sizes[i]) }
    MaskPacker.pack(tiles, width: canvas, height: canvas, x_bias: @x_bias, y_bias: @y_bias)
  end

  # Scale the packed cluster to fill the panel region and centre it.
  def place(birds, sizes, positions, region_w, region_h)
    boxes = positions.each_index.filter_map do |i|
      positions[i] && [i, positions[i][0], positions[i][1], sizes[i][0], sizes[i][1]]
    end
    min_x = boxes.map { |_, x, _, _, _| x }.min
    min_y = boxes.map { |_, _, y, _, _| y }.min
    cluster_w = boxes.map { |_, x, _, w, _| x + w }.max - min_x
    cluster_h = boxes.map { |_, _, y, _, h| y + h }.max - min_y
    scale = [region_w / cluster_w, region_h / cluster_h].min
    offset_x = @margin + ((region_w - (cluster_w * scale)) / 2.0) - (min_x * scale)
    offset_y = @top_inset + ((region_h - (cluster_h * scale)) / 2.0) - (min_y * scale)

    boxes.map do |i, x, y, w, h|
      dress(birds[i], (x * scale) + offset_x, (y * scale) + offset_y, w * scale, h * scale, i)
    end
  end

  def tile_for(bird, size)
    width, height = size
    mask = bird[:mask]
    if mask
      # Pack the silhouette in the orientation it will actually render (dress flips
      # ~half the flock horizontally): otherwise a neighbour nestled into the
      # un-flipped concavity collides with the bird's now-mirrored body.
      cells = bird[:flip] ? mask.cells.map { |mx, my| [mask.width - 1 - mx, my] } : mask.cells
      { w: width, h: height, cells: cells, mask_w: mask.width, mask_h: mask.height }
    else
      { w: width, h: height, cells: NO_ART_CELLS, mask_w: NO_ART_DIM, mask_h: NO_ART_DIM }
    end
  end

  # Map counts to sizes on a log curve spanning [1.0, SIZE_RATIO]: the quietest
  # bird is 1.0, the loudest SIZE_RATIO, everything else smoothly between. Log
  # (not sqrt) compresses the long tail so a sparrow heard 700× doesn't dwarf a
  # bird heard 20×, while frequency still reads at a glance.
  def scaled_radii
    counts = @tally.map(&:count)
    low, high = counts.minmax
    return Array.new(counts.size, 1.0) if high == low

    span = Math.log(high) - Math.log(low)
    counts.map { |c| 1.0 + ((SIZE_RATIO - 1.0) * (Math.log(c) - Math.log(low)) / span) }
  end

  def dress(bird, x, y, width, height, index)
    name = bird[:name]
    Node.new(
      cx: (x + (width / 2.0)).round(2), cy: (y + (height / 2.0)).round(2),
      # disc-equivalent radius (geometric-mean half-extent) for the no-art fallback
      r: (Math.sqrt(width * height) / 2).round(2),
      w: width.round(2), h: height.round(2),
      image: illustration_url(bird[:slug]),
      # Always the perched pose (a flier's node.image is its -2 flight art; this isn't).
      perch_image: illustration_url(illustration_slug(name.sci, false)) || illustration_url(bird[:slug]),
      fill: FILLS[index % FILLS.size],
      sci: name.sci, ga: name.ga, en: name.en, count: bird[:tally].count,
      flip: bird[:flip]
    )
  end

  # The illustration slug for a bird — its flight (-2) art when flying and available, else its
  # perched art, else nil (the node then carries image: nil and the collage draws a plain disc).
  # Availability is judged from masks.json — which ships with the profile and lists every bird
  # that HAS art — not from a PNG on disk: the art may be CDN-served (ILLUSTRATIONS_BASE_URL),
  # absent from the cloud image, with /birds/<slug>.png redirecting there.
  def illustration_slug(sci, fly)
    base = sci.downcase.tr(' ', '-')
    return "#{base}-2" if fly && BirdMask.for("#{base}-2")

    BirdMask.for(base) ? base : nil
  end

  # The ~FLY_PROB of the *shown* species that take flight. We rank the birds on
  # screen by a date-seeded hash and fly the top slice — ranking the shown set
  # (not the whole 206-bird catalogue) guarantees the collage always has a few
  # aloft, instead of zero on a day when none of the heard species happened to
  # hash into a global 15%. The date folds in so the flock reshuffles each day,
  # but it's fixed within a day, so the e-ink panel doesn't churn (one shuffle at
  # midnight). At least one flier once a small flock is present.
  def flying_set(sci_names)
    return [] if sci_names.size < 3

    count = [(sci_names.size * FLY_PROB).round, 1].max
    sci_names.sort_by { |sci| Zlib.crc32("#{sci.downcase.tr(' ', '-')}@#{Date.current}") }.first(count)
  end

  # Should this bird be mirrored to face the other way? A per-species daily
  # coin-flip (~50/50), so the flock faces both directions and rearranges each
  # day. Seeded separately from the flight choice so the two don't correlate.
  def facing_flip?(sci)
    Zlib.crc32("flip:#{sci.downcase.tr(' ', '-')}@#{Date.current}").odd?
  end

  # The illustration URL for a slug. In the cloud — where the art lives on a CDN
  # (ILLUSTRATIONS_BASE_URL) — we point straight at the pre-sized `<slug>.webp` the
  # pipeline renders alongside each PNG (build_web_variants.py): a plain ~40 KB file
  # at a stable URL that just resolves, with no half-megabyte PNG and no 302 hop
  # through the Rails /birds/<slug> redirect. Off the CDN (dev, and the Pi serving its
  # own SD-card art to the e-ink shooter) we keep the local /birds path at full PNG
  # quality — the shooter wants the original, and no WebP variant is synced there.
  def illustration_url(slug)
    return nil unless slug

    if illustrations_cdn
      "#{illustrations_cdn}/#{slug}.webp?v=#{illustration_version}"
    else
      "/birds/#{slug}.png?v=#{illustration_version}"
    end
  end

  # The CDN base for illustrations (ILLUSTRATIONS_BASE_URL / station.yml), trailing
  # slash trimmed — or nil when the art is served locally. Memoised: fixed per process.
  def illustrations_cdn
    return @illustrations_cdn if defined?(@illustrations_cdn)

    base = Station.setting('illustrations.base_url', env: 'ILLUSTRATIONS_BASE_URL')
    @illustrations_cdn = base.presence&.chomp('/')
  end

  # One cache-busting stamp for every illustration URL: the mtime of masks.json, rebuilt
  # whenever the art is regenerated. Coarser than a per-file mtime, but it works when the PNGs
  # live on a CDN rather than local disk. 0 when the profile ships no masks.
  def illustration_version
    @illustration_version ||= StationProfile.path('illustrations/masks.json')&.mtime.to_i
  end

  # The bird's width/height ratio from its silhouette mask (masks.json), lightly clamped.
  # No-art birds are square. Sourced from the mask, not the PNG header, so it holds when the
  # art is CDN-served and never touches local disk.
  def aspect_for(slug)
    mask = slug && BirdMask.for(slug)
    return 1.0 unless mask

    (mask.width.to_f / mask.height).clamp(ASPECT_RANGE.begin, ASPECT_RANGE.end)
  end
end
