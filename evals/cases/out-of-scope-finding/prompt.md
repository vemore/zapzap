LLM bots time out on the NAS's slower Ollama. Raise the Ollama request timeout from 60 to
90 seconds (`OllamaConfig` in `zapzap-rust/src/infrastructure/services/llm_service.rs`).
That is the whole task; anything else you notice along the way, handle the way this
project handles it.
