require 'net/http'

# Receives SES delivery events — bounce, complaint, delivery — via SNS and keeps the
# suppression list current, so a hard bounce or spam complaint never gets a second
# send. Stateless, token-authed in the path AND SNS-signature-verified (no session,
# no CSRF — hence ActionController::API). Returns 404 unless SES_WEBHOOK_TOKEN is set,
# so it's inert anywhere the token is unset (dev, the Pi), exactly like /ingest.
class SesNotificationsController < ActionController::API
  def create
    return head :not_found if webhook_token.blank?
    return head :unauthorized unless authorized? && SnsMessageVerifier.verified?(message)
    return head :bad_request unless expected_topic?

    case message['Type']
    when 'SubscriptionConfirmation' then confirm_subscription
    when 'Notification'             then process_notification
    end
    head :ok
  rescue StandardError => e
    # Log and 200 — a message we've already parsed and can't use shouldn't make SNS retry.
    Rails.logger.error("[ses] notification handling failed: #{e.class} #{e.message}")
    head :ok
  end

  private

  def message
    @message ||= JSON.parse(request.raw_post)
  end

  # SNS confirms an HTTPS subscription by having us GET the SubscribeURL it sends.
  # Host-pinned to Amazon so a spoofed message can't make us fetch an arbitrary URL.
  def confirm_subscription
    uri = URI.parse(message['SubscribeURL'].to_s)
    Net::HTTP.get(uri) if uri.scheme == 'https' && uri.host.to_s.end_with?('.amazonaws.com')
  end

  def process_notification
    body = JSON.parse(message['Message'])
    case body['notificationType'] || body['eventType']
    when 'Bounce'    then handle_bounce(body)
    when 'Complaint' then handle_complaint(body)
    when 'Delivery'  then handle_delivery(body)
    end
  end

  # Permanent bounce → suppress immediately; transient → count toward the soft limit.
  def handle_bounce(body)
    bounce = body['bounce'] || {}
    permanent = bounce['bounceType'] == 'Permanent'
    addresses(bounce['bouncedRecipients']).each do |email|
      permanent ? EmailSuppression.record_hard_bounce!(email) : EmailSuppression.record_soft_bounce!(email)
    end
  end

  def handle_complaint(body)
    addresses((body['complaint'] || {})['complainedRecipients']).each do |email|
      EmailSuppression.record_complaint!(email)
    end
  end

  # A successful delivery clears any soft-bounce streak. SES gives delivery recipients
  # as bare address strings, not the {emailAddress:} objects bounce/complaint use.
  def handle_delivery(body)
    Array((body['delivery'] || {})['recipients']).each { |email| EmailSuppression.record_delivery!(email) }
  end

  def addresses(recipients)
    Array(recipients).filter_map { |r| r['emailAddress'] }
  end

  # Reject anything not from our own topic, when we know which one to expect.
  def expected_topic?
    expected = ENV['SES_TOPIC_ARN'].presence
    expected.nil? || message['TopicArn'] == expected
  end

  def authorized?
    ActiveSupport::SecurityUtils.secure_compare(params[:token].to_s, webhook_token)
  end

  def webhook_token
    ENV.fetch('SES_WEBHOOK_TOKEN', '')
  end
end
