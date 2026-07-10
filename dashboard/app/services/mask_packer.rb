# Silhouette-aware collage packing — a port of the parent repo's raster-bitmask
# nester (its front-end apt.js). Each bird ships a low-res alpha mask. We
# precompute each bird's footprint on a fine occupancy grid once (forward-mapping
# every mask cell to a range of grid cells, so thin parts are fully covered),
# plus a copy dilated by PAD cells that bakes a uniform gap around the silhouette.
# New birds spiral out from the centre and take the closest spot to the cluster's
# centre of mass where their footprint doesn't collide. Result: birds nest into
# each other's concavities — no overlap, no rectangles touching. Deterministic.
class MaskPacker
  STRIDE = 4  # viewport px per occupancy cell — smaller is finer but slower
  PAD = 3     # grid cells of breathing room dilated around each placed bird

  class << self
    # tiles: [{ w:, h:, cells:, mask_w:, mask_h: }] in px (cells = opaque [mx,my]).
    # Returns a top-left [x, y] per tile in input order, or nil if it couldn't fit.
    def pack(tiles, width:, height:, x_bias: 1.0, y_bias: 1.0)
      new(tiles, width, height, x_bias, y_bias).pack
    end
  end

  def initialize(tiles, width, height, x_bias, y_bias)
    @tiles = tiles
    @width = width
    @height = height
    @x_bias = x_bias
    @y_bias = y_bias
    @gw = (width / STRIDE).ceil + (2 * PAD) + 2
    @gh = (height / STRIDE).ceil + (2 * PAD) + 2
    @grid = Array.new(@gw * @gh, false)
    @seed = 0x9E3779B9
  end

  def pack
    prints = @tiles.map { |tile| footprint(tile) }
    result = Array.new(@tiles.size)
    placed = []
    order = (0...@tiles.size).sort_by { |i| -(@tiles[i][:w] * @tiles[i][:h]) }
    cx = @width / 2.0
    cy = @height / 2.0

    order.each_with_index do |i, nth|
      tile = @tiles[i]
      spot = nth.zero? ? [cx - (tile[:w] / 2.0), cy - (tile[:h] / 2.0)] : find_spot(tile, prints[i], placed, cx, cy)
      next if spot.nil?

      stamp(prints[i], spot[0], spot[1])
      placed << tile.merge(x: spot[0], y: spot[1])
      result[i] = spot
    end
    result
  end

  private

  # A deterministic LCG, so the layout is stable for a given tally.
  def rand
    @seed = (@seed * 16_807) % 2_147_483_647
    @seed / 2_147_483_647.0
  end

  # The tile's silhouette as grid-cell offsets from its top-left, computed once:
  # :cells for collision, :dilated (grown by PAD) for stamping the gap.
  def footprint(tile)
    sx = tile[:w].to_f / tile[:mask_w]
    sy = tile[:h].to_f / tile[:mask_h]
    occupied = {}
    tile[:cells].each do |mask_x, mask_y|
      gx0 = (mask_x * sx / STRIDE).to_i
      gx1 = ((mask_x + 1) * sx / STRIDE).to_i
      gy0 = (mask_y * sy / STRIDE).to_i
      gy1 = ((mask_y + 1) * sy / STRIDE).to_i
      gy0.upto(gy1) { |gy| gx0.upto(gx1) { |gx| occupied[(gy << 16) | gx] = true } }
    end
    cells = occupied.keys.map { |key| [key & 0xffff, key >> 16] }
    dilated = {}
    cells.each do |gx, gy|
      (-PAD..PAD).each { |ddy| (-PAD..PAD).each { |ddx| dilated[[gx + ddx, gy + ddy]] = true } }
    end
    { cells: cells, dilated: dilated.keys }
  end

  def collides?(print, base_x, base_y)
    print[:cells].each do |gdx, gdy|
      gx = base_x + gdx
      gy = base_y + gdy
      next if gx.negative? || gx >= @gw || gy.negative? || gy >= @gh

      return true if @grid[(gy * @gw) + gx]
    end
    false
  end

  def stamp(print, tx, ty)
    base_x = (tx / STRIDE).to_i + PAD
    base_y = (ty / STRIDE).to_i + PAD
    print[:dilated].each do |gdx, gdy|
      gx = base_x + gdx
      gy = base_y + gdy
      next if gx.negative? || gx >= @gw || gy.negative? || gy >= @gh

      @grid[(gy * @gw) + gx] = true
    end
  end

  def off_grid?(tile, tx, ty)
    tx.negative? || ty.negative? || (tx + tile[:w]) > @width || (ty + tile[:h]) > @height
  end

  def find_spot(tile, print, placed, cx, cy)
    com_x, com_y = centre_of_mass(placed)
    best = nil
    best_cost = Float::INFINITY
    step = [STRIDE, [tile[:w], tile[:h]].min * 0.05].max
    max_r = [@width, @height].max
    found_ring = nil
    phase = rand * Math::PI * 2
    r = 0.0
    while r <= max_r
      break if found_ring && r > found_ring + (step * 2)

      samples = [36, (r / 1.6).floor].max
      samples.times do |k|
        theta = phase + ((k.to_f / samples) * Math::PI * 2)
        px = cx + (r * @x_bias * Math.cos(theta)) - (tile[:w] / 2.0)
        py = cy + (r * @y_bias * Math.sin(theta)) - (tile[:h] / 2.0)
        next if off_grid?(tile, px, py)
        next if collides?(print, (px / STRIDE).to_i + PAD, (py / STRIDE).to_i + PAD)

        dxx = (px + (tile[:w] / 2.0) - com_x) / @x_bias
        dyy = (py + (tile[:h] / 2.0) - com_y) / @y_bias
        cost = Math.hypot(dxx, dyy) + (rand * step * 0.5)
        if cost < best_cost
          best_cost = cost
          best = [px, py]
        end
      end
      found_ring ||= r if best
      r += step
    end
    best
  end

  def centre_of_mass(placed)
    weight = total_x = total_y = 0.0
    placed.each do |p|
      area = p[:w] * p[:h]
      total_x += (p[:x] + (p[:w] / 2.0)) * area
      total_y += (p[:y] + (p[:h] / 2.0)) * area
      weight += area
    end
    weight.zero? ? [0.0, 0.0] : [total_x / weight, total_y / weight]
  end
end
