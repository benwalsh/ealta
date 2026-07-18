require 'rails_helper'
require 'openssl'
require 'base64'

RSpec.describe SnsMessageVerifier do
  # A throwaway CA-less cert we sign the canonical string with; the verifier fetches
  # its public key (stubbed here) to check the signature.
  let(:key) { OpenSSL::PKey::RSA.new(2048) }
  let(:certificate) do
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=sns.eu-west-1.amazonaws.com')
    cert.public_key = key.public_key
    cert.not_before = Time.utc(2026, 1, 1)
    cert.not_after = Time.utc(2030, 1, 1)
    cert.sign(key, OpenSSL::Digest.new('SHA256'))
    cert
  end
  let(:message) do
    {
      'Type' => 'Notification', 'MessageId' => 'abc', 'TopicArn' => 'arn:aws:sns:eu-west-1:1:t',
      'Message' => '{"notificationType":"Bounce"}', 'Timestamp' => '2026-07-17T00:00:00.000Z',
      'SignatureVersion' => '2', 'SigningCertURL' => 'https://sns.eu-west-1.amazonaws.com/cert.pem'
    }
  end

  # The exact canonical string SNS signs for a Notification (no Subject present).
  def sign(message, digest: 'SHA256')
    canonical = %w[Message MessageId Timestamp TopicArn Type].map { |k| "#{k}\n#{message[k]}\n" }.join
    Base64.strict_encode64(key.sign(OpenSSL::Digest.new(digest), canonical))
  end

  before { allow(described_class).to receive(:fetch).and_return(certificate.to_pem) }

  it 'accepts a correctly signed message' do
    message['Signature'] = sign(message)
    expect(described_class.verified?(message)).to be(true)
  end

  it 'rejects a message whose body was tampered with after signing' do
    message['Signature'] = sign(message)
    message['Message'] = '{"notificationType":"Complaint"}' # changed post-signature
    expect(described_class.verified?(message)).to be(false)
  end

  it 'rejects a signing cert served from a non-Amazon host (never even fetched)' do
    expect(described_class).not_to receive(:fetch)
    message['Signature'] = sign(message)
    message['SigningCertURL'] = 'https://evil.example.com/cert.pem'
    expect(described_class.verified?(message)).to be(false)
  end

  it 'rejects an unknown message type' do
    message['Type'] = 'Nonsense'
    message['Signature'] = sign(message)
    expect(described_class.verified?(message)).to be(false)
  end
end
