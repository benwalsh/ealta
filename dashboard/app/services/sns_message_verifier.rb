require 'net/http'
require 'openssl'
require 'base64'

# Verifies the cryptographic signature on an Amazon SNS message, so a leaked webhook
# token still can't forge a bounce/complaint and grief-suppress arbitrary addresses.
# Pure OpenSSL (no aws-sdk-sns dependency): rebuild the canonical string SNS signed,
# fetch the signing certificate (host-pinned to Amazon's SNS domain), and RSA-verify.
# See docs.aws.amazon.com/sns/latest/dg/sns-verify-signature-of-message.html.
class SnsMessageVerifier
  # The signing cert must be served from Amazon's own SNS host — never an attacker URL.
  CERT_HOST = /\Asns\.[a-z0-9-]+\.amazonaws\.com\z/

  # The exact fields, in this exact order, that SNS signs for each message type.
  SIGNABLE_KEYS = {
    'Notification'             => %w[Message MessageId Subject Timestamp TopicArn Type],
    'SubscriptionConfirmation' => %w[Message MessageId SubscribeURL Timestamp Token TopicArn Type],
    'UnsubscribeConfirmation'  => %w[Message MessageId SubscribeURL Timestamp Token TopicArn Type]
  }.freeze

  class << self
    def verified?(message)
      keys = SIGNABLE_KEYS[message['Type']] or return false

      cert_uri = URI.parse(message['SigningCertURL'].to_s)
      return false unless cert_uri.scheme == 'https' && CERT_HOST.match?(cert_uri.host)

      # Only keys actually present are included (SNS omits Subject when there's none).
      canonical = keys.filter_map { |k| "#{k}\n#{message[k]}\n" if message.key?(k) }.join
      digest = message['SignatureVersion'] == '1' ? OpenSSL::Digest.new('SHA1') : OpenSSL::Digest.new('SHA256')
      certificate = OpenSSL::X509::Certificate.new(fetch(cert_uri))
      certificate.public_key.verify(digest, Base64.decode64(message['Signature'].to_s), canonical)
    rescue StandardError => e
      Rails.logger.warn("[ses] SNS signature verify failed: #{e.class} #{e.message}")
      false
    end

    # Isolated so specs can supply a certificate without a network round-trip.
    def fetch(uri)
      Net::HTTP.get(uri)
    end
  end
end
