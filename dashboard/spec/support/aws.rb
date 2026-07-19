# The suite must never reach a real credential source.
#
# Without this, any spec that touches an AWS-backed path (the species detail endpoint, via
# enrichment) makes the SDK walk its whole credential chain — env, ~/.aws, ECS, and finally
# the EC2 instance metadata endpoint at 169.254.169.254. On a laptop that last hop is a TCP
# connection to an address that isn't there, so the run's speed and outcome depended on
# whether the machine happened to have credentials lying around, and how fast the metadata
# attempt failed. A test suite should not care.
#
# Static dummy credentials stop the chain walk before it starts; stub_responses guarantees no
# request leaves the process. Both are global SDK config, so this covers every client the app
# builds, now and later — not just Bedrock.
#
# NB this deliberately does NOT set SUMMARY_LLM_DISABLED. That would switch every LLM-backed
# caller onto its template path and quietly stop the specs that stub Bedrock.converse from
# exercising the model path at all.

# Bedrock is autoloaded, so its own `require 'aws-sdk-bedrockruntime'` hasn't run yet when
# support files load. aws-sdk-core is what defines Aws.config and Aws::Credentials.
require 'aws-sdk-core'

Aws.config.update(
  credentials:    Aws::Credentials.new('test-akid', 'test-secret'),
  stub_responses: true
)
