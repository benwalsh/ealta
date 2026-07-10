require 'aws-sdk-bedrockruntime'

# The single seam to Amazon Bedrock. Everything model-facing lives behind this one
# class so the rest of the app never touches the AWS SDK directly and tests can stub
# one method. Uses the Converse API, which normalises the request/response shape
# across Bedrock models (Nova included).
#
# Config is env-only (no secrets in code): BEDROCK_REGION, BEDROCK_MODEL_ID, and the
# standard AWS credential chain (env / shared config / instance role). Set
# SUMMARY_LLM_DISABLED=1 to force the caller onto its template path — used in tests
# and on an offline box that should never dial out.
class Bedrock
  DEFAULT_REGION = 'eu-west-1'.freeze
  # The EU cross-region inference profile for Amazon Nova Lite. Confirm the exact id
  # against the account's enabled model access — it must match a profile you can call
  # from the configured region.
  DEFAULT_MODEL = 'eu.amazon.nova-lite-v1:0'.freeze
  # The stronger model used for the enrichment SOURCING pass (Stage 1), which needs
  # tool-use + judgement Nova Lite isn't meant for. A current Claude inference profile
  # (Sonnet 4.5, dated/pinned — Bedrock retires older ones as "Legacy"). Env-driven, so
  # bump ENRICH_MODEL_ID when a newer profile is enabled without a redeploy.
  DEFAULT_ENRICH_MODEL = 'eu.anthropic.claude-sonnet-4-5-20250929-v1:0'.freeze
  MAX_TOKENS = 400
  TEMPERATURE = 0.4

  class << self
    def disabled?
      ENV['SUMMARY_LLM_DISABLED'].present?
    end

    # Send a system prompt + user message through Converse and return the model's
    # plain text. Raises on any transport/credential error — the caller decides how
    # to degrade (keep last-good cache, else template).
    def converse(system:, user:, model_id: self.model_id, max_tokens: MAX_TOKENS, temperature: TEMPERATURE)
      raise 'Bedrock disabled (SUMMARY_LLM_DISABLED)' if disabled?

      response = client.converse(
        model_id:         model_id,
        system:           [{ text: system }],
        messages:         [{ role: 'user', content: [{ text: user }] }],
        inference_config: { max_tokens: max_tokens, temperature: temperature }
      )
      response.output.message.content.map(&:text).join.strip
    end

    # One round of a tool-use conversation. Given the running `messages` (Converse
    # shape) and the `tools` specs, returns the raw response so the caller can drive
    # the loop — read stop_reason, run any requested tool, append the result, call
    # again. Kept transport-only; the Builder owns the loop and the prompt.
    def converse_tools(system:, messages:, tools:, model_id: enrich_model_id, max_tokens: 4000,
                       temperature: TEMPERATURE)
      raise 'Bedrock disabled (SUMMARY_LLM_DISABLED)' if disabled?

      client.converse(
        model_id:         model_id,
        system:           [{ text: system }],
        messages:         messages,
        tool_config:      { tools: tools },
        inference_config: { max_tokens: max_tokens, temperature: temperature }
      )
    end

    def model_id
      ENV.fetch('BEDROCK_MODEL_ID', DEFAULT_MODEL)
    end

    def enrich_model_id
      ENV.fetch('ENRICH_MODEL_ID', DEFAULT_ENRICH_MODEL)
    end

    def region
      ENV.fetch('BEDROCK_REGION', DEFAULT_REGION)
    end

    private

    def client
      @client ||= Aws::BedrockRuntime::Client.new(region: region)
    end
  end
end
