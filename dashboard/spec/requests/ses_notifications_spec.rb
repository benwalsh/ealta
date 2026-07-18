require 'rails_helper'

RSpec.describe 'SES notifications' do
  let(:topic) { 'arn:aws:sns:eu-west-1:1:station-ses-events' }

  around do |example|
    ENV['SES_WEBHOOK_TOKEN'] = 'secret-token'
    ENV['SES_TOPIC_ARN'] = topic
    example.run
    ENV.delete('SES_WEBHOOK_TOKEN')
    ENV.delete('SES_TOPIC_ARN')
  end

  # The signature is verified in sns_message_verifier_spec; here we trust it and test
  # the routing + suppression behaviour.
  before { allow(SnsMessageVerifier).to receive(:verified?).and_return(true) }

  def notify(message, token: 'secret-token')
    post "/webhooks/ses/#{token}", params: message.merge('TopicArn' => message['TopicArn'] || topic), as: :json
  end

  def bounce(type, email)
    { 'Type'    => 'Notification',
      'Message' => { notificationType: 'Bounce',
                     bounce:           { bounceType: type, bouncedRecipients: [{ emailAddress: email }] } }.to_json }
  end

  it 'is 404 when the webhook token is unset (the Pi, dev)' do
    ENV.delete('SES_WEBHOOK_TOKEN')
    notify(bounce('Permanent', 'x@example.com'))
    expect(response).to have_http_status(:not_found)
  end

  it 'is 401 for the wrong path token' do
    notify(bounce('Permanent', 'x@example.com'), token: 'wrong')
    expect(response).to have_http_status(:unauthorized)
  end

  it 'is 401 when the SNS signature does not verify' do
    allow(SnsMessageVerifier).to receive(:verified?).and_return(false)
    notify(bounce('Permanent', 'x@example.com'))
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects a message from an unexpected topic' do
    notify(bounce('Permanent', 'x@example.com').merge('TopicArn' => 'arn:aws:sns:eu-west-1:1:someone-else'))
    expect(response).to have_http_status(:bad_request)
  end

  it 'suppresses a hard-bounced address immediately' do
    notify(bounce('Permanent', 'gone@example.com'))
    expect(response).to have_http_status(:ok)
    expect(EmailSuppression.suppressed?('gone@example.com')).to be(true)
  end

  it 'does not suppress a single transient (soft) bounce' do
    notify(bounce('Transient', 'slow@example.com'))
    expect(EmailSuppression.suppressed?('slow@example.com')).to be(false)
    expect(EmailSuppression.find_by(email: 'slow@example.com').soft_bounces).to eq(1)
  end

  it 'suppresses a complained-about address immediately' do
    complaint = { complainedRecipients: [{ emailAddress: 'cross@example.com' }] }
    notify({ 'Type'    => 'Notification',
             'Message' => { notificationType: 'Complaint', complaint: complaint }.to_json })
    expect(EmailSuppression.suppressed?('cross@example.com')).to be(true)
  end

  it 'confirms an SNS subscription by fetching the SubscribeURL' do
    url = 'https://sns.eu-west-1.amazonaws.com/?Action=ConfirmSubscription&Token=xyz'
    expect(Net::HTTP).to receive(:get).with(URI.parse(url))
    notify({ 'Type' => 'SubscriptionConfirmation', 'SubscribeURL' => url })
    expect(response).to have_http_status(:ok)
  end
end
