//! LLM Service
//!
//! Abstraction for LLM API calls: Ollama (`/api/chat`) and AWS Bedrock (the Converse API).
//! Both take a system prompt and a user message, with no template of one model's own, so
//! the model is a setting: `OLLAMA_MODEL`, `AWS_BEDROCK_MODEL_ID`.

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
    /// Invoke LLM with system and user prompts; the answer's text, without its reasoning
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

/// Tokens a model may generate for one answer, its reasoning included: a reasoning model
/// thinks before it answers, and an answer cut off before its text is a fallback move
pub const MAX_ANSWER_TOKENS: u32 = 2048;

/// How hard a reasoning model thinks: `low` keeps a bot's turn to a second or two
pub const REASONING_EFFORT: &str = "low";

/// The reasoning effort to ask `model` for: gpt-oss models take one (Bedrock's
/// `reasoning_effort`, Ollama's `think`); any other model gets none, since Bedrock refuses
/// a field a model does not know ("extraneous key [reasoning_effort] is not permitted")
pub fn reasoning_effort(model: &str) -> Option<&'static str> {
    model.contains("gpt-oss").then_some(REASONING_EFFORT)
}

/// Ollama service configuration
#[derive(Debug, Clone)]
pub struct OllamaConfig {
    pub base_url: String,
    pub model: String,
    pub timeout_secs: u64,
    pub max_tokens: u32,
}

impl Default for OllamaConfig {
    fn default() -> Self {
        Self {
            base_url: std::env::var("OLLAMA_BASE_URL")
                .unwrap_or_else(|_| "http://localhost:11434".to_string()),
            model: std::env::var("OLLAMA_MODEL").unwrap_or_else(|_| "llama3.2".to_string()),
            timeout_secs: 60,
            max_tokens: MAX_ANSWER_TOKENS,
        }
    }
}

/// Ollama `/api/chat` request body
#[derive(Debug, Serialize)]
struct OllamaChatRequest<'a> {
    model: &'a str,
    messages: [OllamaMessage<'a>; 2],
    stream: bool,
    /// A gpt-oss model's reasoning effort; other models take none
    #[serde(skip_serializing_if = "Option::is_none")]
    think: Option<&'static str>,
    options: OllamaOptions,
}

#[derive(Debug, Serialize)]
struct OllamaMessage<'a> {
    role: &'static str,
    content: &'a str,
}

#[derive(Debug, Serialize)]
struct OllamaOptions {
    num_predict: u32,
}

/// Ollama `/api/chat` response: a thinking model's reasoning comes apart from its content
#[derive(Debug, Deserialize)]
struct OllamaChatResponse {
    message: OllamaReply,
}

#[derive(Debug, Deserialize)]
struct OllamaReply {
    #[serde(default)]
    content: String,
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

    /// The chat request: the system prompt and the user message, the model's own template
    /// applied by Ollama
    fn chat_request<'a>(
        &'a self,
        system_prompt: &'a str,
        user_prompt: &'a str,
    ) -> OllamaChatRequest<'a> {
        OllamaChatRequest {
            model: &self.config.model,
            messages: [
                OllamaMessage {
                    role: "system",
                    content: system_prompt,
                },
                OllamaMessage {
                    role: "user",
                    content: user_prompt,
                },
            ],
            stream: false,
            think: reasoning_effort(&self.config.model),
            options: OllamaOptions {
                num_predict: self.config.max_tokens,
            },
        }
    }
}

/// The answer of a chat response: its content, never its thinking
fn ollama_answer(response: OllamaChatResponse) -> Result<String, LlmError> {
    let content = response.message.content;
    if content.trim().is_empty() {
        return Err(LlmError::InvalidResponse(
            "no answer after the reasoning".to_string(),
        ));
    }
    Ok(content)
}

#[async_trait]
impl LlmService for OllamaService {
    async fn invoke(&self, system_prompt: &str, user_prompt: &str) -> Result<String, LlmError> {
        let url = format!("{}/api/chat", self.config.base_url);
        let request = self.chat_request(system_prompt, user_prompt);

        debug!("Calling Ollama API: {}", url);
        let start = std::time::Instant::now();

        let response = self.client.post(&url).json(&request).send().await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            error!("Ollama API error: {} - {}", status, body);
            return Err(LlmError::InvalidResponse(format!("Status: {}", status)));
        }

        let answer = ollama_answer(response.json().await?)?;
        debug!(
            "Ollama response received in {:?}: {} chars",
            start.elapsed(),
            answer.len()
        );

        Ok(answer)
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

/// The Bedrock model when `AWS_BEDROCK_MODEL_ID` is not set: OpenAI's gpt-oss-120b, served
/// on demand in us-east-1, us-east-2, eu-west-1, eu-central-1, ap-northeast-1, ap-south-1
/// and ap-southeast-2 (not eu-west-3; checked 2026-09-29)
pub const DEFAULT_BEDROCK_MODEL_ID: &str = "openai.gpt-oss-120b-1:0";

/// AWS Bedrock service configuration
#[derive(Debug, Clone)]
pub struct BedrockConfig {
    pub region: String,
    pub model_id: String,
    /// Longest a call may take, retries included: the bot's turn falls back past it
    pub timeout_secs: u64,
    pub max_tokens: u32,
}

impl Default for BedrockConfig {
    fn default() -> Self {
        Self {
            region: std::env::var("AWS_BEDROCK_REGION").unwrap_or_else(|_| "us-east-1".to_string()),
            model_id: std::env::var("AWS_BEDROCK_MODEL_ID")
                .unwrap_or_else(|_| DEFAULT_BEDROCK_MODEL_ID.to_string()),
            timeout_secs: 30,
            max_tokens: MAX_ANSWER_TOKENS,
        }
    }
}

/// Tokens and calls a Bedrock service has used since it started
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct LlmUsage {
    pub calls: u64,
    pub input_tokens: u64,
    pub output_tokens: u64,
}

/// AWS Bedrock LLM service implementation, on the Converse API
#[cfg(feature = "bedrock")]
pub struct BedrockService {
    client: aws_sdk_bedrockruntime::Client,
    config: BedrockConfig,
    usage: std::sync::Mutex<LlmUsage>,
}

#[cfg(feature = "bedrock")]
impl BedrockService {
    pub async fn new(config: BedrockConfig) -> Self {
        let timeouts = aws_config::timeout::TimeoutConfig::builder()
            .operation_timeout(Duration::from_secs(config.timeout_secs))
            .build();
        let aws_config = aws_config::from_env()
            .region(aws_config::Region::new(config.region.clone()))
            .timeout_config(timeouts)
            .load()
            .await;

        let client = aws_sdk_bedrockruntime::Client::new(&aws_config);

        info!(
            "BedrockService initialized: {} (model: {})",
            config.region, config.model_id
        );

        Self {
            client,
            config,
            usage: std::sync::Mutex::new(LlmUsage::default()),
        }
    }

    /// The model this service calls
    pub fn model_id(&self) -> &str {
        &self.config.model_id
    }

    /// Calls and tokens used so far
    pub fn usage(&self) -> LlmUsage {
        *self.usage.lock().unwrap_or_else(|e| e.into_inner())
    }
}

/// Health-check prompt: one word asked, at most `HEALTH_CHECK_MAX_TOKENS` tokens generated,
/// so that a warm model answers well within `STARTUP_PROBE_TIMEOUT`. A reasoning model may
/// spend them all thinking: the call answering is what the check asks, not its text.
#[cfg(feature = "bedrock")]
const HEALTH_CHECK_SYSTEM: &str = "Answer with the single word OK.";
#[cfg(feature = "bedrock")]
const HEALTH_CHECK_USER: &str = "OK";
#[cfg(feature = "bedrock")]
const HEALTH_CHECK_MAX_TOKENS: u32 = 16;

/// The Converse request: the system prompt, one user message, the token budget, and a
/// gpt-oss model's reasoning effort. Nothing in it belongs to one model's prompt format.
#[cfg(feature = "bedrock")]
fn converse_request(
    client: &aws_sdk_bedrockruntime::Client,
    config: &BedrockConfig,
    system_prompt: &str,
    user_prompt: &str,
    max_tokens: u32,
) -> aws_sdk_bedrockruntime::operation::converse::builders::ConverseFluentBuilder {
    use aws_sdk_bedrockruntime::types::{
        ContentBlock, ConversationRole, InferenceConfiguration, Message, SystemContentBlock,
    };
    use aws_smithy_types::Document;

    let message = Message::builder()
        .role(ConversationRole::User)
        .content(ContentBlock::Text(user_prompt.to_string()))
        .build()
        .expect("a message with a role and a content block");
    let request = client
        .converse()
        .model_id(&config.model_id)
        .system(SystemContentBlock::Text(system_prompt.to_string()))
        .messages(message)
        .inference_config(
            InferenceConfiguration::builder()
                .max_tokens(max_tokens.min(i32::MAX as u32) as i32)
                .build(),
        );
    match reasoning_effort(&config.model_id) {
        Some(effort) => request.additional_model_request_fields(Document::Object(
            [(
                "reasoning_effort".to_string(),
                Document::String(effort.to_string()),
            )]
            .into(),
        )),
        None => request,
    }
}

/// The answer of a Converse response: its text blocks, never its reasoning block
#[cfg(feature = "bedrock")]
fn converse_answer(
    response: &aws_sdk_bedrockruntime::operation::converse::ConverseOutput,
) -> Result<String, LlmError> {
    let message = response
        .output()
        .and_then(|output| output.as_message().ok())
        .ok_or_else(|| LlmError::InvalidResponse("no message in the response".to_string()))?;
    let text: String = message
        .content()
        .iter()
        .filter_map(|block| block.as_text().ok())
        .map(String::as_str)
        .collect();
    if text.trim().is_empty() {
        return Err(LlmError::InvalidResponse(format!(
            "no answer after the reasoning (stop reason {})",
            response.stop_reason()
        )));
    }
    Ok(text)
}

#[cfg(feature = "bedrock")]
impl BedrockService {
    async fn converse(
        &self,
        system_prompt: &str,
        user_prompt: &str,
        max_tokens: u32,
    ) -> Result<aws_sdk_bedrockruntime::operation::converse::ConverseOutput, LlmError> {
        let start = std::time::Instant::now();
        let response = converse_request(
            &self.client,
            &self.config,
            system_prompt,
            user_prompt,
            max_tokens,
        )
        .send()
        .await
        .map_err(|e| {
            LlmError::InvalidResponse(
                aws_sdk_bedrockruntime::error::DisplayErrorContext(e).to_string(),
            )
        })?;

        let (input, output) = response
            .usage()
            .map(|u| {
                (
                    u.input_tokens().max(0) as u64,
                    u.output_tokens().max(0) as u64,
                )
            })
            .unwrap_or_default();
        {
            let mut usage = self.usage.lock().unwrap_or_else(|e| e.into_inner());
            usage.calls += 1;
            usage.input_tokens += input;
            usage.output_tokens += output;
        }
        debug!(
            "Bedrock {} answered in {:?}: {} tokens in, {} out, stop reason {}",
            self.config.model_id,
            start.elapsed(),
            input,
            output,
            response.stop_reason()
        );
        Ok(response)
    }
}

#[cfg(feature = "bedrock")]
#[async_trait]
impl LlmService for BedrockService {
    async fn invoke(&self, system_prompt: &str, user_prompt: &str) -> Result<String, LlmError> {
        let response = self
            .converse(system_prompt, user_prompt, self.config.max_tokens)
            .await?;
        converse_answer(&response)
    }

    async fn health_check(&self) -> bool {
        self.converse(
            HEALTH_CHECK_SYSTEM,
            HEALTH_CHECK_USER,
            HEALTH_CHECK_MAX_TOKENS,
        )
        .await
        .map_err(|e| warn!("AWS Bedrock health check failed: {}", e))
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
    fn test_reasoning_effort_only_for_gpt_oss() {
        assert_eq!(reasoning_effort("openai.gpt-oss-120b-1:0"), Some("low"));
        assert_eq!(reasoning_effort("gpt-oss:20b"), Some("low"));
        assert_eq!(reasoning_effort("us.meta.llama3-3-70b-instruct-v1:0"), None);
        assert_eq!(reasoning_effort("llama3.2"), None);
    }

    fn ollama(model: &str) -> OllamaService {
        OllamaService::new(OllamaConfig {
            base_url: "http://localhost:11434".to_string(),
            model: model.to_string(),
            timeout_secs: 1,
            max_tokens: MAX_ANSWER_TOKENS,
        })
    }

    #[test]
    fn test_ollama_chat_request_is_messages_without_a_template() {
        let service = ollama("gpt-oss:20b");
        let body =
            serde_json::to_value(service.chat_request("System prompt", "User prompt")).unwrap();

        assert_eq!(body["model"], "gpt-oss:20b");
        assert_eq!(body["stream"], false);
        assert_eq!(body["think"], "low");
        assert_eq!(body["options"]["num_predict"], MAX_ANSWER_TOKENS);
        assert_eq!(
            body["messages"],
            serde_json::json!([
                {"role": "system", "content": "System prompt"},
                {"role": "user", "content": "User prompt"},
            ])
        );
        assert!(!body.to_string().contains("<|"), "{body}");

        // A model that does not reason is not asked to
        let body = serde_json::to_value(ollama("llama3.2").chat_request("s", "u")).unwrap();
        assert!(body.get("think").is_none(), "{body}");
    }

    #[test]
    fn test_ollama_answer_is_the_content_not_the_thinking() {
        let response: OllamaChatResponse = serde_json::from_value(serde_json::json!({
            "model": "gpt-oss:20b",
            "message": {
                "role": "assistant",
                "thinking": "The pair of kings sheds 26 points: {\"play\": 2}",
                "content": "{\"play\": 1}",
            },
            "done": true,
        }))
        .unwrap();
        assert_eq!(ollama_answer(response).unwrap(), "{\"play\": 1}");

        // Cut off while thinking: no answer
        let response: OllamaChatResponse = serde_json::from_value(serde_json::json!({
            "message": {"role": "assistant", "thinking": "Let me see", "content": ""},
        }))
        .unwrap();
        assert!(ollama_answer(response).is_err());
    }

    #[cfg(feature = "bedrock")]
    mod bedrock {
        use super::super::*;
        use aws_sdk_bedrockruntime::operation::converse::ConverseOutput;
        use aws_sdk_bedrockruntime::types::{
            ContentBlock, ConversationRole, ConverseOutput as Output, Message,
            ReasoningContentBlock, ReasoningTextBlock, StopReason, SystemContentBlock,
        };
        use aws_smithy_types::Document;

        fn client() -> aws_sdk_bedrockruntime::Client {
            let config = aws_sdk_bedrockruntime::Config::builder()
                .behavior_version(aws_sdk_bedrockruntime::config::BehaviorVersion::latest())
                .region(aws_sdk_bedrockruntime::config::Region::new("us-east-1"))
                .build();
            aws_sdk_bedrockruntime::Client::from_conf(config)
        }

        fn config(model_id: &str) -> BedrockConfig {
            BedrockConfig {
                region: "us-east-1".to_string(),
                model_id: model_id.to_string(),
                timeout_secs: 30,
                max_tokens: MAX_ANSWER_TOKENS,
            }
        }

        #[test]
        fn test_converse_request_holds_no_model_template() {
            let client = client();
            let request = converse_request(
                &client,
                &config(DEFAULT_BEDROCK_MODEL_ID),
                "System prompt",
                "User prompt",
                MAX_ANSWER_TOKENS,
            );
            let input = request.as_input();

            assert_eq!(
                input.get_model_id().as_deref(),
                Some("openai.gpt-oss-120b-1:0")
            );
            let system = input.get_system().as_ref().unwrap();
            assert_eq!(
                system,
                &[SystemContentBlock::Text("System prompt".to_string())]
            );
            let messages = input.get_messages().as_ref().unwrap();
            assert_eq!(messages.len(), 1);
            assert_eq!(messages[0].role(), &ConversationRole::User);
            assert_eq!(
                messages[0].content(),
                &[ContentBlock::Text("User prompt".to_string())]
            );
            assert_eq!(
                input.get_inference_config().as_ref().unwrap().max_tokens(),
                Some(MAX_ANSWER_TOKENS as i32)
            );
            let fields = input
                .get_additional_model_request_fields()
                .as_ref()
                .unwrap();
            assert_eq!(
                fields,
                &Document::Object(
                    [(
                        "reasoning_effort".to_string(),
                        Document::String("low".to_string())
                    )]
                    .into()
                )
            );
            // No Llama template, nor any other model's
            let everything = format!("{input:?}");
            assert!(!everything.contains("<|begin_of_text|>"), "{everything}");
            assert!(!everything.contains("<|"), "{everything}");
        }

        #[test]
        fn test_converse_request_for_another_model_needs_no_change() {
            let client = client();
            let model = "us.meta.llama3-3-70b-instruct-v1:0";
            let request = converse_request(&client, &config(model), "s", "u", 64);
            let input = request.as_input();

            assert_eq!(input.get_model_id().as_deref(), Some(model));
            // Llama refuses a field it does not know
            assert!(input.get_additional_model_request_fields().is_none());
        }

        #[test]
        fn test_bedrock_health_check_is_cheap() {
            let client = client();
            let request = converse_request(
                &client,
                &config(DEFAULT_BEDROCK_MODEL_ID),
                HEALTH_CHECK_SYSTEM,
                HEALTH_CHECK_USER,
                HEALTH_CHECK_MAX_TOKENS,
            );
            let max_tokens = request
                .as_input()
                .get_inference_config()
                .as_ref()
                .unwrap()
                .max_tokens()
                .unwrap();
            assert!((1..=16).contains(&max_tokens), "max_tokens {max_tokens}");
        }

        fn response(content: Vec<ContentBlock>, stop: StopReason) -> ConverseOutput {
            let message = Message::builder()
                .role(ConversationRole::Assistant)
                .set_content(Some(content))
                .build()
                .unwrap();
            ConverseOutput::builder()
                .output(Output::Message(message))
                .stop_reason(stop)
                .build()
                .unwrap()
        }

        fn reasoning(text: &str) -> ContentBlock {
            ContentBlock::ReasoningContent(ReasoningContentBlock::ReasoningText(
                ReasoningTextBlock::builder().text(text).build().unwrap(),
            ))
        }

        #[test]
        fn test_converse_answer_is_the_text_not_the_reasoning() {
            let answer = converse_answer(&response(
                vec![
                    reasoning("Playing the kings sheds the most: {\"play\": 2}"),
                    ContentBlock::Text("{\"play\": 1}".to_string()),
                ],
                StopReason::EndTurn,
            ));
            assert_eq!(answer.unwrap(), "{\"play\": 1}");
        }

        #[test]
        fn test_converse_answer_cut_off_while_reasoning_is_an_error() {
            let answer = converse_answer(&response(
                vec![reasoning("Let me count the points")],
                StopReason::MaxTokens,
            ));
            let error = answer.unwrap_err().to_string();
            assert!(error.contains("max_tokens"), "{error}");
        }
    }
}
