require 'aws-sdk-s3'
require 'open3'

# Generates a station's bird illustration on demand, in the CLOUD, and publishes it to the
# illustrations bucket — so both the public site and the Pi (which redirects to that CDN for any
# art it lacks) pick it up, with no desktop run and no per-device sync. Generate once, everyone
# gets it.
#
# CLOUD ONLY, and structurally so: it needs the illustrations bucket (ILLUSTRATIONS_BUCKET) and the
# Python pipeline, both of which live only in the cloud. The device never generates art — it loads
# finished assets — so on the Pi this is simply off (no bucket, and `bundle --without cloud` drops
# aws-sdk-s3 entirely).
#
# The STYLE is the station's own: the pipeline reads the profile's illustration prompt
# (STATION_PROFILE, baked into the cloud image), so each station renders in its own hand (one
# profile might ask for Irish linotype, another for watercolour). Nothing style-specific lives here.
class Illustrations
  # The perched illustration and, when the pipeline renders one, the in-flight variant.
  POSES = ['', '-2'].freeze
  PIPELINE = Rails.root.join('../pipeline/scripts').to_s.freeze
  # The working illustrations set the pipeline reads/writes — the full library, seeded from the
  # bucket at worker boot, so a set-wide masks.json rebuild sees every bird, not just the new one.
  WORKDIR = ENV.fetch('ILLUSTRATIONS_WORKDIR', '/tmp/illustrations')

  class << self
    # On only when there's a bucket to publish to — the cloud. Off on the Pi, where this must never
    # run: the device loads finished assets, it does not make them.
    def enabled?
      bucket.present?
    end

    # The illustration slug for a scientific name — matches ApplicationHelper#bird_illustration so
    # the key we publish is the one the app asks for.
    def slug(sci)
      sci.downcase.tr(' ', '-')
    end

    # Is this bird's art already in the bucket? Idempotency for the job: a species can be enqueued
    # twice (two ingest batches before the first render lands), and rendering is expensive.
    def exists?(sci)
      client.head_object(bucket: bucket, key: "#{slug(sci)}.png")
      true
    rescue Aws::S3::Errors::NotFound
      false
    end

    # Render <sci> in the station's style and publish it (+ its silhouette mask + web variant) to
    # the bucket. Logs each step so a missing key or a pipeline failure is visible, never silent —
    # and raises on failure so the job retries rather than swallowing it.
    def generate(sci, common_name = nil)
      name = common_name.presence || BirdName.lookup(sci).en
      Rails.logger.info("Illustrations: rendering #{sci} (#{name}) in the station's style…")
      render(sci, name)
      published = publish(sci)
      Rails.logger.info("Illustrations: published #{published.join(', ')} to #{bucket}")
      published
    end

    private

    def bucket
      ENV['ILLUSTRATIONS_BUCKET'].presence
    end

    def client
      @client ||= Aws::S3::Client.new(region: ENV.fetch('AWS_REGION', 'eu-west-1'))
    end

    # Run the illustration pipeline for one species into the working set: draw (the profile's
    # prompt, via Gemini when GEMINI_API_KEY is set — else the free flat fallback), cut the ground
    # out, then rebuild the collage masks and the web variants over the whole set. Reuses the
    # existing pipeline scripts unchanged by pointing STATION_PROFILE at the working dir.
    def render(sci, common_name)
      env = { 'STATION_PROFILE' => WORKDIR }
      gemini = ENV['GEMINI_API_KEY'].present?
      Rails.logger.info("Illustrations: #{gemini ? 'Gemini' : 'flat (no GEMINI_API_KEY)'} render of #{sci}")
      if gemini
        run(env, 'pregen.py', '--species', "#{sci}|#{common_name}", '--poses', '1', '--force')
        run(env, 'cutout_flood.py')
      else
        run(env, 'flatgen.py', '--species', "#{sci}|#{common_name}", '--force')
      end
      run(env, 'build_masks.py')
      run(env, 'build_web_variants.py')
    end

    # Push the new bird's files + the rebuilt manifest to the bucket. The mask manifest is set-wide,
    # so it is always re-uploaded; the poses are uploaded when the pipeline produced them.
    def publish(sci)
      keys = pose_files(sci) + ['masks.json']
      keys.each do |key|
        path = File.join(WORKDIR, 'illustrations', key)
        next unless File.exist?(path)

        client.put_object(bucket: bucket, key: key, body: File.open(path, 'rb'),
                          content_type: content_type(key))
      end
      keys.select { |k| File.exist?(File.join(WORKDIR, 'illustrations', k)) }
    end

    # The PNG + WebP for each pose the pipeline may have written.
    def pose_files(sci)
      POSES.flat_map { |p| ["#{slug(sci)}#{p}.png", "#{slug(sci)}#{p}.webp"] }
    end

    def content_type(key)
      case File.extname(key)
      when '.png' then 'image/png'
      when '.webp' then 'image/webp'
      else 'application/json'
      end
    end

    # One pipeline step, failing loudly. Isolated so specs can stub it and so a non-zero exit is
    # logged with the script that failed rather than a bare error.
    def run(env, script, *)
      out, status = Open3.capture2e(env, 'python', File.join(PIPELINE, script), *)
      return if status.success?

      raise "pipeline #{script} failed (exit #{status.exitstatus}): #{out.lines.last(3).join.strip}"
    end
  end
end
