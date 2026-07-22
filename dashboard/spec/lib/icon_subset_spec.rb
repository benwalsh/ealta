require 'rails_helper'

# The Tabler icon webfont is subset at build time to only the glyphs the app uses — 447KB down
# to ~4KB (bin/build-icon-subset). The subset is checked in, so it can go stale: add a ti-* class
# and forget to regenerate, and that one icon renders as a blank square in production while
# everything looks fine locally (dev may still have the full font cached). This is the backstop —
# it re-derives what the code uses and asserts the checked-in subset covers all of it.
RSpec.describe 'Tabler icon subset', type: :model do
  let(:subset_css) { Rails.root.join('app/javascript/styles/tabler-icons-subset.css') }
  let(:subset_woff2) { Rails.root.join('app/javascript/styles/tabler-icons-subset.woff2') }
  let(:tabler_css) { Rails.root.join('node_modules/@tabler/icons-webfont/dist/tabler-icons.min.css') }

  # Same extraction the generator uses: every ti-<name> under app/, minus the letter-prefixed
  # false positives ("anti-repetition" → ti-repetition) the lookbehind drops.
  def icons_referenced_in_code
    Rails.root.glob('app/**/*').filter_map do |path|
      next unless File.file?(path)

      # scrub: app/ holds binary assets too (fonts, images) — drop invalid byte sequences
      # rather than raise, exactly as the generator's errors="ignore" read does.
      File.read(path, encoding: 'UTF-8').scrub.scan(/(?<![a-zA-Z])ti-[a-z0-9-]+/)
    end.flatten.to_set
  end

  # Which of those are real Tabler classes (the generator ships exactly these).
  def real_tabler_classes
    tabler_css.read.scan(/\.(ti-[a-z0-9-]+):before/).flatten.to_set
  end

  it 'ships the subset artifacts' do
    expect(subset_css).to exist
    expect(subset_woff2).to exist
  end

  it 'covers every real icon the code references' do
    referenced = icons_referenced_in_code & real_tabler_classes
    in_subset = subset_css.read.scan(/\.(ti-[a-z0-9-]+):before/).flatten.to_set

    missing = referenced - in_subset
    expect(missing).to be_empty,
                       "Icons used in app/ but absent from the subset: #{missing.to_a.sort.join(', ')}.\n" \
                       'Run `bin/build-icon-subset` and commit the regenerated files.'
  end

  # A weather/almanac icon that is NOT a real Tabler class renders as tofu (this is how the
  # ti-fog / ti-cloud-drizzle bug hid). Every ti-* the code names as an icon must resolve.
  it 'references no icon that Tabler does not define' do
    unknown = icons_referenced_in_code - real_tabler_classes

    expect(unknown).to be_empty,
                       'ti-* names used in app/ that do not exist in Tabler (blank squares): ' \
                       "#{unknown.to_a.sort.join(', ')}"
  end

  it 'stays tiny — the whole point of subsetting' do
    expect(subset_woff2.size).to be < 50_000 # the full font is ~447KB; a healthy subset is single-digit KB
  end

  # The subset is worthless unless the entrypoints actually IMPORT it: a prior commit shipped a
  # generated subset while both entrypoints still pulled the full 447KB webfont, so nothing
  # improved. Guard the wiring, not just the artifact — no entrypoint may import the full font.
  it 'is the font the entrypoints actually load (no entrypoint pulls the full webfont)' do
    entrypoints = Rails.root.glob('app/javascript/entrypoints/*')
    offenders = entrypoints.select { |f| File.read(f).include?('@tabler/icons-webfont') }

    expect(offenders).to be_empty,
                         'These entrypoints import the FULL Tabler webfont instead of the subset: ' \
                         "#{offenders.map { |f| File.basename(f) }.join(', ')}"
  end
end
