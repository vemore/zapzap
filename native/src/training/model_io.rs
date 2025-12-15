//! Model I/O - Save and load model weights using safetensors format
//!
//! This module provides functionality to:
//! - Save model weights to safetensors files
//! - Load model weights from safetensors files
//! - Export model metadata (architecture info)

use safetensors::tensor::{SafeTensors, TensorView};
use safetensors::serialize;
use std::collections::HashMap;
use std::fs;
use std::path::Path;

use super::config::TrainingConfig;

/// Model metadata stored alongside weights
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct ModelMetadata {
    /// Model version
    pub version: String,
    /// Input dimension
    pub input_dim: usize,
    /// Hidden layer dimension
    pub hidden_dim: usize,
    /// Value stream hidden dimension
    pub value_hidden: usize,
    /// Advantage stream hidden dimension
    pub advantage_hidden: usize,
    /// Number of training steps
    pub training_steps: u64,
    /// Number of games played
    pub games_played: u64,
    /// Final epsilon value
    pub final_epsilon: f32,
    /// Average loss at save time
    pub avg_loss: f32,
    /// Win rate at save time
    pub win_rate: f32,
    /// Timestamp of save
    pub timestamp: String,
}

impl Default for ModelMetadata {
    fn default() -> Self {
        Self {
            version: "1.0.0".to_string(),
            input_dim: 45,
            hidden_dim: 128,
            value_hidden: 64,
            advantage_hidden: 32,
            training_steps: 0,
            games_played: 0,
            final_epsilon: 1.0,
            avg_loss: 0.0,
            win_rate: 0.0,
            timestamp: chrono_timestamp(),
        }
    }
}

impl ModelMetadata {
    pub fn from_config(config: &TrainingConfig) -> Self {
        Self {
            input_dim: config.input_dim,
            hidden_dim: config.hidden_dim,
            value_hidden: config.value_hidden,
            advantage_hidden: config.advantage_hidden,
            ..Default::default()
        }
    }
}

/// Get current timestamp as string
fn chrono_timestamp() -> String {
    // Simple timestamp without chrono dependency
    use std::time::{SystemTime, UNIX_EPOCH};
    let duration = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    format!("{}", duration.as_secs())
}

/// Model I/O operations
pub struct ModelIO;

impl ModelIO {
    /// Save weights to safetensors file
    ///
    /// # Arguments
    /// * `path` - Path to save file (with .safetensors extension)
    /// * `weights` - Flat vector of model weights
    /// * `metadata` - Optional model metadata
    pub fn save_weights(
        path: &str,
        weights: &[f32],
        metadata: Option<ModelMetadata>,
    ) -> Result<(), String> {
        // Create tensor data as bytes - store in a variable to extend lifetime
        let shape = vec![weights.len()];
        let data: Vec<u8> = weights
            .iter()
            .flat_map(|f| f.to_le_bytes())
            .collect();

        // Prepare metadata
        let mut meta_map: HashMap<String, String> = HashMap::new();
        if let Some(meta) = metadata {
            if let Ok(json) = serde_json::to_string(&meta) {
                meta_map.insert("metadata".to_string(), json);
            }
        }
        meta_map.insert("shape".to_string(), format!("{}", weights.len()));
        meta_map.insert("dtype".to_string(), "float32".to_string());

        // Create TensorView with reference to owned data
        let tensor_view = TensorView::new(
            safetensors::Dtype::F32,
            shape,
            &data,  // Reference to owned Vec<u8>
        ).map_err(|e| format!("Failed to create tensor view: {}", e))?;

        let tensor_data = vec![("weights", tensor_view)];

        let serialized = serialize(tensor_data, &Some(meta_map))
            .map_err(|e| format!("Failed to serialize: {}", e))?;

        // Ensure parent directory exists
        if let Some(parent) = Path::new(path).parent() {
            fs::create_dir_all(parent)
                .map_err(|e| format!("Failed to create directory: {}", e))?;
        }

        // Write to file
        fs::write(path, serialized)
            .map_err(|e| format!("Failed to write file: {}", e))?;

        Ok(())
    }

    /// Load weights from safetensors file
    ///
    /// # Returns
    /// Tuple of (weights, metadata)
    pub fn load_weights(path: &str) -> Result<(Vec<f32>, Option<ModelMetadata>), String> {
        // Read file
        let data = fs::read(path)
            .map_err(|e| format!("Failed to read file: {}", e))?;

        // Parse safetensors to get metadata first
        let metadata: Option<ModelMetadata> = SafeTensors::read_metadata(&data)
            .ok()
            .and_then(|(_, safe_meta)| {
                safe_meta.metadata().as_ref().and_then(|meta_map| {
                    meta_map.get("metadata").and_then(|json| {
                        serde_json::from_str(json).ok()
                    })
                })
            });

        // Now deserialize to get tensors
        let tensors = SafeTensors::deserialize(&data)
            .map_err(|e| format!("Failed to deserialize: {}", e))?;

        // Get weights tensor
        let weights_tensor = tensors.tensor("weights")
            .map_err(|e| format!("Failed to get weights tensor: {}", e))?;

        // Convert to f32 vec
        let weights_bytes = weights_tensor.data();
        let weights: Vec<f32> = weights_bytes
            .chunks_exact(4)
            .map(|chunk| {
                f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]])
            })
            .collect();

        Ok((weights, metadata))
    }

    /// Check if model file exists
    pub fn model_exists(path: &str) -> bool {
        Path::new(path).exists()
    }

    /// Get model metadata without loading weights
    pub fn get_metadata(path: &str) -> Result<Option<ModelMetadata>, String> {
        let data = fs::read(path)
            .map_err(|e| format!("Failed to read file: {}", e))?;

        // Read only metadata, avoiding full tensor deserialization
        let metadata = SafeTensors::read_metadata(&data)
            .ok()
            .and_then(|(_, safe_meta)| {
                safe_meta.metadata().as_ref().and_then(|meta_map| {
                    meta_map.get("metadata").and_then(|json| {
                        serde_json::from_str(json).ok()
                    })
                })
            });

        Ok(metadata)
    }

    /// Save training checkpoint (weights + training state)
    pub fn save_checkpoint(
        path: &str,
        weights: &[f32],
        config: &TrainingConfig,
        training_steps: u64,
        games_played: u64,
        epsilon: f32,
        avg_loss: f32,
        win_rate: f32,
    ) -> Result<(), String> {
        let metadata = ModelMetadata {
            version: "1.0.0".to_string(),
            input_dim: config.input_dim,
            hidden_dim: config.hidden_dim,
            value_hidden: config.value_hidden,
            advantage_hidden: config.advantage_hidden,
            training_steps,
            games_played,
            final_epsilon: epsilon,
            avg_loss,
            win_rate,
            timestamp: chrono_timestamp(),
        };

        Self::save_weights(path, weights, Some(metadata))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    fn temp_path(name: &str) -> String {
        let dir = env::temp_dir();
        dir.join(format!("zapzap_test_{}.safetensors", name))
            .to_string_lossy()
            .to_string()
    }

    #[test]
    fn test_save_load_weights() {
        let path = temp_path("save_load");
        let weights: Vec<f32> = (0..100).map(|i| i as f32 * 0.1).collect();

        // Save
        let result = ModelIO::save_weights(&path, &weights, None);
        assert!(result.is_ok(), "Save failed: {:?}", result);

        // Load
        let (loaded_weights, _) = ModelIO::load_weights(&path).expect("Load failed");

        // Compare
        assert_eq!(loaded_weights.len(), weights.len());
        for (a, b) in loaded_weights.iter().zip(weights.iter()) {
            assert!((a - b).abs() < 1e-6, "Weights mismatch: {} vs {}", a, b);
        }

        // Cleanup
        let _ = fs::remove_file(&path);
    }

    #[test]
    fn test_save_load_with_metadata() {
        let path = temp_path("metadata");
        let weights: Vec<f32> = vec![1.0, 2.0, 3.0];
        let metadata = ModelMetadata {
            version: "test".to_string(),
            training_steps: 1000,
            games_played: 5000,
            ..Default::default()
        };

        // Save
        ModelIO::save_weights(&path, &weights, Some(metadata.clone())).expect("Save failed");

        // Load
        let (loaded_weights, loaded_meta) = ModelIO::load_weights(&path).expect("Load failed");

        assert_eq!(loaded_weights.len(), 3);
        assert!(loaded_meta.is_some());
        let loaded_meta = loaded_meta.unwrap();
        assert_eq!(loaded_meta.version, "test");
        assert_eq!(loaded_meta.training_steps, 1000);
        assert_eq!(loaded_meta.games_played, 5000);

        // Cleanup
        let _ = fs::remove_file(&path);
    }

    #[test]
    fn test_model_exists() {
        let path = temp_path("exists");

        assert!(!ModelIO::model_exists(&path));

        let weights = vec![1.0f32];
        ModelIO::save_weights(&path, &weights, None).expect("Save failed");

        assert!(ModelIO::model_exists(&path));

        let _ = fs::remove_file(&path);
    }

    #[test]
    fn test_save_checkpoint() {
        let path = temp_path("checkpoint");
        let weights: Vec<f32> = vec![0.1, 0.2, 0.3];
        let config = TrainingConfig::default();

        let result = ModelIO::save_checkpoint(
            &path,
            &weights,
            &config,
            10000,
            50000,
            0.05,
            0.15,
            0.25,
        );

        assert!(result.is_ok());

        let (_, meta) = ModelIO::load_weights(&path).expect("Load failed");
        let meta = meta.expect("Metadata missing");

        assert_eq!(meta.training_steps, 10000);
        assert_eq!(meta.games_played, 50000);
        assert!((meta.final_epsilon - 0.05).abs() < 1e-6);
        assert!((meta.avg_loss - 0.15).abs() < 1e-6);
        assert!((meta.win_rate - 0.25).abs() < 1e-6);

        let _ = fs::remove_file(&path);
    }
}
