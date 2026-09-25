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

/// Longest wait for an LLM service's health check at startup, before the port is bound
pub const STARTUP_PROBE_TIMEOUT: Duration = Duration::from_secs(10);

/// Health-check an LLM service at startup, waiting at most `limit`; returns the service to keep.
///
/// The probe runs before the port is bound, so it cannot wait long. A service that answers
/// its health check is kept, one that fails it is dropped. One that has not answered at
/// `limit` (a cold model) is kept unverified: its first real call decides, and a bot whose
/// call fails plays its fallback strategy.
pub async fn probe_within<S: LlmService>(what: &str, limit: Duration, service: S) -> Option<S> {
    match tokio::time::timeout(limit, service.health_check()).await {
        Ok(true) => Some(service),
        Ok(false) => None,
        Err(_) => {
            warn!(
                "{what} health check did not answer within {limit:?} - kept unverified, \
                 the first bot call decides"
            );
            Some(service)
        }
    }
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
            model: std::env::var("OLLAMA_MODEL").unwrap_or_else(|_| "llama3.2".to_string()),
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

        let response = self.client.post(&url).json(&request).send().await?;

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
            region: std::env::var("AWS_BEDROCK_REGION").unwrap_or_else(|_| "us-east-1".to_string()),
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

/// Health-check prompt: one word asked, at most `HEALTH_CHECK_MAX_GEN_LEN` tokens generated,
/// so that a warm model answers well within `STARTUP_PROBE_TIMEOUT`
#[cfg(any(feature = "bedrock", test))]
const HEALTH_CHECK_SYSTEM: &str = "Answer with the single word OK.";
#[cfg(any(feature = "bedrock", test))]
const HEALTH_CHECK_USER: &str = "OK";
#[cfg(any(feature = "bedrock", test))]
const HEALTH_CHECK_MAX_GEN_LEN: u32 = 5;

/// The Bedrock Llama request body
#[cfg(any(feature = "bedrock", test))]
fn bedrock_payload(
    system_prompt: &str,
    user_prompt: &str,
    max_gen_len: u32,
    temperature: f32,
) -> serde_json::Value {
    let prompt = format!(
        "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n{}<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n{}<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n",
        system_prompt, user_prompt
    );

    serde_json::json!({
        "prompt": prompt,
        "max_gen_len": max_gen_len,
        "temperature": temperature,
    })
}

#[cfg(feature = "bedrock")]
impl BedrockService {
    async fn invoke_with(
        &self,
        system_prompt: &str,
        user_prompt: &str,
        max_gen_len: u32,
    ) -> Result<String, LlmError> {
        use aws_sdk_bedrockruntime::primitives::Blob;

        let payload = bedrock_payload(
            system_prompt,
            user_prompt,
            max_gen_len,
            self.config.temperature,
        );

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
        let result: serde_json::Value =
            serde_json::from_slice(body).map_err(|e| LlmError::InvalidResponse(e.to_string()))?;

        result
            .get("generation")
            .and_then(|v| v.as_str())
            .map(|s| s.to_string())
            .ok_or_else(|| LlmError::InvalidResponse("No generation in response".to_string()))
    }
}

#[cfg(feature = "bedrock")]
#[async_trait]
impl LlmService for BedrockService {
    async fn invoke(&self, system_prompt: &str, user_prompt: &str) -> Result<String, LlmError> {
        self.invoke_with(system_prompt, user_prompt, self.config.max_tokens)
            .await
    }

    async fn health_check(&self) -> bool {
        self.invoke_with(
            HEALTH_CHECK_SYSTEM,
            HEALTH_CHECK_USER,
            HEALTH_CHECK_MAX_GEN_LEN,
        )
        .await
        .is_ok()
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

    /// A service whose health check answers `healthy` after `delay`
    struct ProbedLlmService {
        delay: Duration,
        healthy: bool,
    }

    #[async_trait]
    impl LlmService for ProbedLlmService {
        async fn invoke(&self, _: &str, _: &str) -> Result<String, LlmError> {
            Err(LlmError::Unavailable)
        }

        async fn health_check(&self) -> bool {
            tokio::time::sleep(self.delay).await;
            self.healthy
        }
    }

    #[tokio::test]
    async fn test_probe_within_keeps_a_slow_service_unverified() {
        let started = std::time::Instant::now();
        let service = ProbedLlmService {
            delay: Duration::from_secs(3600),
            healthy: false,
        };

        // A cold model: the boot goes on at the limit, and the service stays for the bots
        let kept = probe_within("cold", Duration::from_millis(50), service).await;

        assert!(kept.is_some());
        assert!(started.elapsed() < Duration::from_secs(5));
    }

    #[tokio::test]
    async fn test_probe_within_keeps_an_available_service() {
        let service = MockLlmService::new("OK");

        assert!(probe_within("mock", STARTUP_PROBE_TIMEOUT, service)
            .await
            .is_some());
    }

    #[tokio::test]
    async fn test_probe_within_drops_a_failing_service() {
        let service = ProbedLlmService {
            delay: Duration::ZERO,
            healthy: false,
        };

        assert!(probe_within("down", STARTUP_PROBE_TIMEOUT, service)
            .await
            .is_none());
    }

    #[test]
    fn test_bedrock_health_check_is_cheap() {
        let payload = bedrock_payload(
            HEALTH_CHECK_SYSTEM,
            HEALTH_CHECK_USER,
            HEALTH_CHECK_MAX_GEN_LEN,
            0.3,
        );

        let max_gen_len = payload["max_gen_len"].as_u64().unwrap();
        assert!((1..=5).contains(&max_gen_len), "max_gen_len {max_gen_len}");
        let prompt = payload["prompt"].as_str().unwrap();
        assert!(prompt.contains("<|start_header_id|>user<|end_header_id|>\n\nOK<|eot_id|>"));
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
