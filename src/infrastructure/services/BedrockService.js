/**
 * BedrockService
 * Infrastructure service for AWS Bedrock LLM API calls (Llama 3.3)
 */

const { BedrockRuntimeClient, InvokeModelCommand } = require('@aws-sdk/client-bedrock-runtime');
const logger = require('../../../logger');

class BedrockService {
    /**
     * @param {Object} options - Service configuration
     * @param {string} options.region - AWS region (default: from env or 'us-east-1')
     * @param {string} options.modelId - Bedrock model ID (default: from env or Llama 3.3 70B)
     * @param {number} options.maxTokens - Max tokens in response (default: 512)
     * @param {number} options.temperature - Temperature for generation (default: 0.3)
     * @param {number} options.timeout - Request timeout in ms (default: 30000)
     */
    constructor(options = {}) {
        this.region = options.region || process.env.AWS_BEDROCK_REGION || 'us-east-1';
        this.modelId = options.modelId || process.env.AWS_BEDROCK_MODEL_ID || 'meta.llama3-3-70b-instruct-v1:0';
        this.maxTokens = options.maxTokens || 512;
        this.temperature = options.temperature || 0.3; // Lower for more deterministic game decisions
        this.timeout = options.timeout || 30000; // 30 second timeout

        // Initialize Bedrock client
        // Uses AWS credentials from environment (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
        // or IAM role when running on AWS infrastructure
        this.client = new BedrockRuntimeClient({
            region: this.region,
        });

        logger.info('BedrockService initialized', {
            region: this.region,
            modelId: this.modelId,
            maxTokens: this.maxTokens,
            temperature: this.temperature
        });
    }

    /**
     * Invoke Llama 3.3 model with a raw prompt
     * @param {string} prompt - Full prompt including system and user messages
     * @returns {Promise<string>} Model response text
     */
    async invoke(prompt) {
        const startTime = Date.now();

        try {
            // Llama 3.3 on Bedrock payload format
            const payload = {
                prompt: prompt,
                max_gen_len: this.maxTokens,
                temperature: this.temperature,
            };

            const command = new InvokeModelCommand({
                modelId: this.modelId,
                body: JSON.stringify(payload),
                contentType: 'application/json',
                accept: 'application/json',
            });

            // Create timeout promise
            const timeoutPromise = new Promise((_, reject) => {
                setTimeout(() => reject(new Error('Bedrock API timeout')), this.timeout);
            });

            // Race between API call and timeout
            const response = await Promise.race([
                this.client.send(command),
                timeoutPromise
            ]);

            const responseBody = JSON.parse(new TextDecoder().decode(response.body));
            const generation = responseBody.generation || '';

            const duration = Date.now() - startTime;
            logger.debug('Bedrock API call completed', {
                modelId: this.modelId,
                durationMs: duration,
                inputLength: prompt.length,
                outputLength: generation.length
            });

            return generation;
        } catch (error) {
            const duration = Date.now() - startTime;
            logger.error('Bedrock API call failed', {
                error: error.message,
                errorCode: error.name,
                modelId: this.modelId,
                durationMs: duration,
            });
            throw error;
        }
    }

    /**
     * Invoke with structured prompt using Llama 3.3 instruction format
     * @param {string} systemPrompt - System context (game rules)
     * @param {string} userPrompt - User message (current game situation)
     * @returns {Promise<string>} Model response
     */
    async invokeWithContext(systemPrompt, userPrompt) {
        // Llama 3.3 instruction format
        const fullPrompt = `<|begin_of_text|><|start_header_id|>system<|end_header_id|>

${systemPrompt}<|eot_id|><|start_header_id|>user<|end_header_id|}

${userPrompt}<|eot_id|><|start_header_id|>assistant<|end_header_id|>

`;
        return this.invoke(fullPrompt);
    }

    /**
     * Check if the service is properly configured and accessible
     * @returns {Promise<boolean>} True if service is operational
     */
    async healthCheck() {
        try {
            // Simple ping with minimal tokens
            const testPrompt = `<|begin_of_text|><|start_header_id|>user<|end_header_id|>

Say "OK"<|eot_id|><|start_header_id|>assistant<|end_header_id|>

`;
            const originalMaxTokens = this.maxTokens;
            this.maxTokens = 10;

            const response = await this.invoke(testPrompt);

            this.maxTokens = originalMaxTokens;
            return response && response.length > 0;
        } catch (error) {
            logger.warn('BedrockService health check failed', { error: error.message });
            return false;
        }
    }

    /**
     * Get service configuration info
     * @returns {Object} Configuration details
     */
    getConfig() {
        return {
            region: this.region,
            modelId: this.modelId,
            maxTokens: this.maxTokens,
            temperature: this.temperature,
            timeout: this.timeout
        };
    }
}

module.exports = BedrockService;
