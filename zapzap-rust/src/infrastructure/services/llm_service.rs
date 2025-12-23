//! LLM Service
//!
//! Abstraction for LLM API calls (supports Ollama and AWS Bedrock)

use async_trait::async_trait;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tracing::{debug, error, info, warn};

/// LLM service error
#[derive(Debug, thiserror::Error)]
pub enum LlmError {
    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),
    #[error("Timeout")]
    Timeout,
    #[error("Service unavailable")]
    Unavailable,
    #[error("Invalid response: {0}")]
    InvalidResponse(String),
}

/// LLM Service trait
#[async_trait]
pub trait LlmService: Send + Sync {
    /// Invoke LLM with system and user prompts
    async fn invoke(&self, system_prompt: &str, user_prompt: &str) -> Result<String, LlmError>;

    /// Check if service is available
    async fn health_check(&self) -> bool;
}

/// Ollama service configuration
#[derive(Debug, Clone)]
pub struct OllamaConfig {
    pub base_url: String,
    pub model: String,
    pub timeout_secs: u64,
    pub temperature: f32,
    pub max_tokens: u32,
}

impl Default for OllamaConfig {
    fn default() -> Self {
        Self {
            base_url: std::env::var("OLLAMA_BASE_URL")
                .unwrap_or_else(|_| "http://localhost:11434".to_string()),
            model: std::env::var("OLLAMA_MODEL")
                .unwrap_or_else(|_| "llama3.2".to_string()),
            timeout_secs: 60,
            temperature: 0.3,
            max_tokens: 512,
        }
    }
}

/// Ollama request body
#[derive(Debug, Serialize)]
struct OllamaRequest {
    model: String,
    prompt: String,
    stream: bool,
    options: OllamaOptions,
}

#[derive(Debug, Serialize)]
struct OllamaOptions {
    temperature: f32,
    num_predict: u32,
}

/// Ollama response
#[derive(Debug, Deserialize)]
struct OllamaResponse {
    response: String,
    #[serde(default)]
    done: bool,
}

/// Ollama LLM service implementation
pub struct OllamaService {
    client: Client,
    config: OllamaConfig,
}

impl OllamaService {
    pub fn new(config: OllamaConfig) -> Self {
        let client = Client::builder()
            .timeout(Duration::from_secs(config.timeout_secs))
            .build()
            .expect("Failed to create HTTP client");

        info!(
            "OllamaService initialized: {} (model: {})",
            config.base_url, config.model
        );

        Self { client, config }
    }

    pub fn with_defaults() -> Self {
        Self::new(OllamaConfig::default())
    }

    /// Format prompt in Llama instruction format
    fn format_prompt(&self, system_prompt: &str, user_prompt: &str) -> String {
        format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n{}<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n{}<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n",
            system_prompt, user_prompt
        )
    }
}

#[async_trait]
impl LlmService for OllamaService {
    async fn invoke(&self, system_prompt: &str, user_prompt: &str) -> Result<String, LlmError> {
        let prompt = self.format_prompt(system_prompt, user_prompt);
        let url = format!("{}/api/generate", self.config.base_url);

        let request = OllamaRequest {
            model: self.config.model.clone(),
            prompt,
            stream: false,
            options: OllamaOptions {
                temperature: self.config.temperature,
                num_predict: self.config.max_tokens,
            },
        };

        debug!("Calling Ollama API: {}", url);
        let start = std::time::Instant::now();

        let response = self
            .client
            .post(&url)
            .json(&request)
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            error!("Ollama API error: {} - {}", status, body);
            return Err(LlmError::InvalidResponse(format!("Status: {}", status)));
        }

        let result: OllamaResponse = response.json().await?;
        let duration = start.elapsed();

        debug!(
            "Ollama response received in {:?}: {} chars",
            duration,
            result.response.len()
        );

        Ok(result.response)
    }

    async fn health_check(&self) -> bool {
        let url = format!("{}/api/tags", self.config.base_url);

        match self.client.get(&url).send().await {
            Ok(response) => response.status().is_success(),
            Err(e) => {
                warn!("Ollama health check failed: {}", e);
                false
            }
        }
    }
}

/// AWS Bedrock service configuration
#[derive(Debug, Clone)]
pub struct BedrockConfig {
    pub region: String,
    pub model_id: String,
    pub timeout_secs: u64,
    pub temperature: f32,
    pub max_tokens: u32,
}

impl Default for BedrockConfig {
    fn default() -> Self {
        Self {
            region: std::env::var("AWS_BEDROCK_REGION")
                .unwrap_or_else(|_| "us-east-1".to_string()),
            model_id: std::env::var("AWS_BEDROCK_MODEL_ID")
                .unwrap_or_else(|_| "meta.llama3-3-70b-instruct-v1:0".to_string()),
            timeout_secs: 30,
            temperature: 0.3,
            max_tokens: 512,
        }
    }
}

/// AWS Bedrock LLM service implementation
/// Note: This requires aws-sdk-bedrockruntime crate to be added
#[cfg(feature = "bedrock")]
pub struct BedrockService {
    client: aws_sdk_bedrockruntime::Client,
    config: BedrockConfig,
}

#[cfg(feature = "bedrock")]
impl BedrockService {
    pub async fn new(config: BedrockConfig) -> Self {
        let aws_config = aws_config::from_env()
            .region(aws_config::Region::new(config.region.clone()))
            .load()
            .await;

        let client = aws_sdk_bedrockruntime::Client::new(&aws_config);

        info!(
            "BedrockService initialized: {} (model: {})",
            config.region, config.model_id
        );

        Self { client, config }
    }
}

#[cfg(feature = "bedrock")]
#[async_trait]
impl LlmService for BedrockService {
    async fn invoke(&self, system_prompt: &str, user_prompt: &str) -> Result<String, LlmError> {
        use aws_sdk_bedrockruntime::primitives::Blob;
        use serde_json::json;

        let prompt = format!(
            "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n{}<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n{}<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n",
            system_prompt, user_prompt
        );

        let payload = json!({
            "prompt": prompt,
            "max_gen_len": self.config.max_tokens,
            "temperature": self.config.temperature,
        });

        let response = self
            .client
            .invoke_model()
            .model_id(&self.config.model_id)
            .body(Blob::new(payload.to_string().into_bytes()))
            .content_type("application/json")
            .accept("application/json")
            .send()
            .await
            .map_err(|e| LlmError::InvalidResponse(e.to_string()))?;

        let body = response.body.as_ref();
        let result: serde_json::Value = serde_json::from_slice(body)
            .map_err(|e| LlmError::InvalidResponse(e.to_string()))?;

        result
            .get("generation")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
            .ok_or_else(|| LlmError::InvalidResponse("No generation in response".to_string()))
    }

    async fn health_check(&self) -> bool {
        // Simple check - try to invoke with minimal tokens
        match self.invoke("Say OK", "").await {
            Ok(_) => true,
            Err(_) => false,
        }
    }
}

/// Mock LLM service for testing
pub struct MockLlmService {
    response: String,
}

impl MockLlmService {
    pub fn new(response: &str) -> Self {
        Self {
            response: response.to_string(),
        }
    }
}

#[async_trait]
impl LlmService for MockLlmService {
    async fn invoke(&self, _system_prompt: &str, _user_prompt: &str) -> Result<String, LlmError> {
        Ok(self.response.clone())
    }

    async fn health_check(&self) -> bool {
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_mock_llm_service() {
        let service = MockLlmService::new("Test response");
        let result = service.invoke("system", "user").await;
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), "Test response");
    }

    #[test]
    fn test_ollama_prompt_format() {
        let service = OllamaService::with_defaults();
        let prompt = service.format_prompt("System prompt", "User prompt");
        assert!(prompt.contains("System prompt"));
        assert!(prompt.contains("User prompt"));
        assert!(prompt.contains("<|start_header_id|>system<|end_header_id|>"));
    }
}
