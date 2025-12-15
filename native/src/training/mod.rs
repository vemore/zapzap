//! Training module for DRL bot using burn framework
//!
//! This module implements:
//! - DuelingDQN neural network with 4 decision heads
//! - Prioritized Experience Replay (PER) buffer
//! - Parallel game simulation with rayon
//! - Training loop with Double DQN
//! - TransitionCollector for recording gameplay
//! - Model I/O with safetensors format

pub mod collector;
pub mod config;
pub mod dueling_dqn;
pub mod model_io;
pub mod replay_buffer;
pub mod sum_tree;
pub mod trainer;
pub mod transition;

pub use collector::TransitionCollector;
pub use config::TrainingConfig;
pub use dueling_dqn::{DecisionType, DuelingDQN, DuelingDQNConfig, ACTION_DIMS};
pub use model_io::{ModelIO, ModelMetadata};
pub use replay_buffer::PrioritizedReplayBuffer;
pub use sum_tree::SumTree;
pub use trainer::{Trainer, TrainingState};
pub use transition::{Transition, TransitionBatch};

// Backend type aliases for convenience
use burn_autodiff::Autodiff;
use burn_ndarray::NdArray;

/// CPU backend type for inference
pub type CpuBackend = NdArray<f32>;

/// Autodiff backend type for training
pub type TrainingBackend = Autodiff<NdArray<f32>>;

/// Feature dimension (must match FeatureExtractor)
pub const FEATURE_DIM: usize = 45;

#[cfg(test)]
mod tests {
    use super::*;
    use burn::prelude::*;
    use burn::tensor::TensorData;

    #[test]
    fn test_backend_compiles() {
        // Simple test to verify burn compiles correctly
        let device = <CpuBackend as burn::tensor::backend::Backend>::Device::default();
        let tensor: burn::tensor::Tensor<CpuBackend, 2> =
            burn::tensor::Tensor::zeros([1, FEATURE_DIM], &device);
        assert_eq!(tensor.dims(), [1, FEATURE_DIM]);
    }

    #[test]
    fn test_cross_architecture_weight_transfer() {
        use crate::fast_dqn::FastDQN;
        use crate::fast_dqn::DecisionType as FastDecisionType;

        // Create DuelingDQN (burn)
        let device = <CpuBackend as burn::tensor::backend::Backend>::Device::default();
        let config = DuelingDQNConfig::default();
        let dqn_burn = DuelingDQN::<CpuBackend>::new(&config, &device);

        // Extract weights
        let weights = dqn_burn.get_weights_flat();
        println!("Extracted {} weights from DuelingDQN", weights.len());
        assert_eq!(weights.len(), 25105, "Weight count mismatch");

        // Create FastDQN with SAME weights directly (no transposition)
        // Copy weights from burn directly to test forward pass equivalence
        let mut fast_dqn = FastDQN::with_seed(99999);
        fast_dqn.set_weights_flat(&weights);

        // Debug: Let's verify the raw burn weights to understand the format
        let burn_shared1_w = dqn_burn.get_shared1_weights_raw();
        println!("\n=== RAW BURN SHARED1 WEIGHTS (first 10, stored as [out, in]) ===");
        for (i, w) in burn_shared1_w.iter().take(10).enumerate() {
            println!("  raw[{}] = {:.6}", i, w);
        }

        // The exported format is [in, out], so element [0] corresponds to weight (i=0, o=0)
        // and element [1] corresponds to (i=0, o=1)
        println!("\n=== EXPORTED SHARED1 (first 10, should be [in, out] format) ===");
        for (i, w) in weights.iter().take(10).enumerate() {
            // For [in, out] format: index = i * out_dim + o = i * 128 + o
            // So index 0 = (i=0, o=0), index 1 = (i=0, o=1), ..., index 127 = (i=0, o=127)
            // index 128 = (i=1, o=0), etc.
            let in_idx = i / 128;
            let out_idx = i % 128;
            println!("  exported[{}] = {:.6} (i={}, o={})", i, w, in_idx, out_idx);
        }

        // Check consistency: exported[i * 128 + o] should equal raw[o * 45 + i]
        println!("\n=== VERIFYING TRANSPOSITION ===");
        let mut trans_errors = 0;
        for i in 0..3 {
            for o in 0..3 {
                let exported_idx = i * 128 + o;
                let raw_idx = o * 45 + i;
                let exported_val = weights[exported_idx];
                let raw_val = burn_shared1_w.get(raw_idx).copied().unwrap_or(f32::NAN);
                let matches = (exported_val - raw_val).abs() < 1e-6;
                if !matches {
                    trans_errors += 1;
                }
                println!("  (i={}, o={}): exported[{}]={:.4}, raw[{}]={:.4} {}",
                    i, o, exported_idx, exported_val, raw_idx, raw_val,
                    if matches { "✓" } else { "✗" });
            }
        }
        if trans_errors > 0 {
            println!("WARNING: {} transposition errors found!", trans_errors);
        }

        // Now verify the FastDQN internal weights match what burn expects
        // FastDQN.set_weights expects [in, out] and stores as [out, in]
        // Let's verify the internal FastDQN weights match burn's raw weights
        let fast_internal = fast_dqn.get_shared1_internal_weights();
        println!("\n=== VERIFYING FASTDQN INTERNAL WEIGHTS ===");
        println!("FastDQN internal[0..10] (should be [out, in] format):");
        for (i, w) in fast_internal.iter().take(10).enumerate() {
            println!("  fast_internal[{}] = {:.6}", i, w);
        }
        println!("\nBurn raw[0..10] (stored as [out, in]):");
        for (i, w) in burn_shared1_w.iter().take(10).enumerate() {
            println!("  burn_raw[{}] = {:.6}", i, w);
        }

        // Check if FastDQN internal matches burn raw
        let mut internal_match = 0;
        let mut internal_mismatch = 0;
        for (i, (f, b)) in fast_internal.iter().zip(burn_shared1_w.iter()).enumerate() {
            if (f - b).abs() < 1e-5 {
                internal_match += 1;
            } else {
                internal_mismatch += 1;
                if internal_mismatch <= 10 {
                    println!("Internal weight mismatch [{}]: fast={:.6}, burn={:.6}", i, f, b);
                }
            }
        }
        println!("\nInternal weight comparison: {} match, {} mismatch", internal_match, internal_mismatch);

        // Now check ALL layers to find where divergence happens
        // Get burn's raw weights for each layer
        let burn_shared2_w = dqn_burn.get_shared2_weights_raw();
        let burn_value1_w = dqn_burn.get_value1_weights_raw();
        let burn_value2_w = dqn_burn.get_value2_weights_raw();
        let burn_adv_hs_1_w = dqn_burn.get_adv_hand_size_l1_weights_raw();
        let burn_adv_hs_2_w = dqn_burn.get_adv_hand_size_l2_weights_raw();

        // Get FastDQN's internal weights for each layer
        let (fast_s2_w, fast_v1_w, fast_v2_w, fast_ahs1_w, fast_ahs2_w) = fast_dqn.get_all_layer_weights();

        // Compare shared2
        let s2_match = burn_shared2_w.iter().zip(fast_s2_w.iter())
            .filter(|(a, b)| (*a - *b).abs() < 1e-5).count();
        println!("\nShared2 weights: {}/{} match", s2_match, burn_shared2_w.len());

        // Compare value1
        let v1_match = burn_value1_w.iter().zip(fast_v1_w.iter())
            .filter(|(a, b)| (*a - *b).abs() < 1e-5).count();
        println!("Value1 weights: {}/{} match", v1_match, burn_value1_w.len());

        // Compare value2
        let v2_match = burn_value2_w.iter().zip(fast_v2_w.iter())
            .filter(|(a, b)| (*a - *b).abs() < 1e-5).count();
        println!("Value2 weights: {}/{} match", v2_match, burn_value2_w.len());

        // Compare advantage hand_size layer 1
        let ahs1_match = burn_adv_hs_1_w.iter().zip(fast_ahs1_w.iter())
            .filter(|(a, b)| (*a - *b).abs() < 1e-5).count();
        println!("AdvHandSize L1 weights: {}/{} match", ahs1_match, burn_adv_hs_1_w.len());

        // Compare advantage hand_size layer 2
        let ahs2_match = burn_adv_hs_2_w.iter().zip(fast_ahs2_w.iter())
            .filter(|(a, b)| (*a - *b).abs() < 1e-5).count();
        println!("AdvHandSize L2 weights: {}/{} match", ahs2_match, burn_adv_hs_2_w.len());

        // Print first mismatches for non-matching layers
        if s2_match < burn_shared2_w.len() {
            println!("\nShared2 first 5 mismatches:");
            for (i, (a, b)) in burn_shared2_w.iter().zip(fast_s2_w.iter()).enumerate().take(5) {
                println!("  [{}]: burn={:.6}, fast={:.6}, diff={:.6}", i, a, b, (a - b).abs());
            }
        }
        if ahs2_match < burn_adv_hs_2_w.len() {
            println!("\nAdvHS L2 first 5 entries:");
            for (i, (a, b)) in burn_adv_hs_2_w.iter().zip(fast_ahs2_w.iter()).enumerate().take(5) {
                println!("  [{}]: burn={:.6}, fast={:.6}, diff={:.6}", i, a, b, (a - b).abs());
            }
        }

        // Check biases too!
        let burn_s1_bias = dqn_burn.get_shared1_bias_raw();
        let burn_s2_bias = dqn_burn.get_shared2_bias_raw();
        let burn_v1_bias = dqn_burn.get_value1_bias_raw();
        let burn_v2_bias = dqn_burn.get_value2_bias_raw();
        let burn_ahs1_bias = dqn_burn.get_adv_hand_size_l1_bias_raw();
        let burn_ahs2_bias = dqn_burn.get_adv_hand_size_l2_bias_raw();

        let (fast_s1_bias, fast_s2_bias, fast_v1_bias, fast_v2_bias, fast_ahs1_bias, fast_ahs2_bias) = fast_dqn.get_all_biases();

        println!("\n=== BIAS COMPARISON ===");
        let s1b_match = burn_s1_bias.iter().zip(fast_s1_bias.iter())
            .filter(|(a, b)| (*a - *b).abs() < 1e-5).count();
        let s2b_match = burn_s2_bias.iter().zip(fast_s2_bias.iter())
            .filter(|(a, b)| (*a - *b).abs() < 1e-5).count();
        let v1b_match = burn_v1_bias.iter().zip(fast_v1_bias.iter())
            .filter(|(a, b)| (*a - *b).abs() < 1e-5).count();
        let ahs1b_match = burn_ahs1_bias.iter().zip(fast_ahs1_bias.iter())
            .filter(|(a, b)| (*a - *b).abs() < 1e-5).count();
        let ahs2b_match = burn_ahs2_bias.iter().zip(fast_ahs2_bias.iter())
            .filter(|(a, b)| (*a - *b).abs() < 1e-5).count();

        println!("Shared1 bias: {}/{} match", s1b_match, burn_s1_bias.len());
        println!("Shared2 bias: {}/{} match", s2b_match, burn_s2_bias.len());
        println!("Value1 bias: {}/{} match", v1b_match, burn_v1_bias.len());
        println!("Value2 bias: burn={:.6}, fast={:.6}", burn_v2_bias, fast_v2_bias);
        println!("AdvHS L1 bias: {}/{} match", ahs1b_match, burn_ahs1_bias.len());
        println!("AdvHS L2 bias: {}/{} match", ahs2b_match, burn_ahs2_bias.len());

        // Print first bias mismatches if any
        if s1b_match < burn_s1_bias.len() {
            println!("\nShared1 bias mismatches (first 5):");
            for (i, (a, b)) in burn_s1_bias.iter().zip(fast_s1_bias.iter()).enumerate().take(5) {
                if (a - b).abs() >= 1e-5 {
                    println!("  [{}]: burn={:.6}, fast={:.6}", i, a, b);
                }
            }
        }

        // Test input
        let input = [0.5f32; FEATURE_DIM];

        // Get Q-values from DuelingDQN (burn)
        let input_tensor: burn::tensor::Tensor<CpuBackend, 2> = burn::tensor::Tensor::from_data(
            TensorData::new(input.to_vec(), [1, FEATURE_DIM]),
            &device,
        );

        // Compare intermediate activations
        println!("\n=== COMPARING INTERMEDIATE ACTIVATIONS ===");

        // Get intermediate activations from burn
        let (burn_h1, burn_h2, burn_value) = dqn_burn.forward_debug(input_tensor.clone());
        let burn_h1_data = burn_h1.into_data();
        let burn_h1_slice = burn_h1_data.as_slice::<f32>().unwrap();
        let burn_h2_data = burn_h2.into_data();
        let burn_h2_slice = burn_h2_data.as_slice::<f32>().unwrap();

        // Get intermediate activations from FastDQN
        let (fast_h1, fast_h2, fast_value) = fast_dqn.forward_debug(&input);

        println!("Shared1 output (h1) - first 5:");
        println!("  burn: {:?}", &burn_h1_slice[..5]);
        println!("  fast: {:?}", &fast_h1[..5]);

        println!("\nShared2 output (h2) - first 5:");
        println!("  burn: {:?}", &burn_h2_slice[..5]);
        println!("  fast: {:?}", &fast_h2[..5]);

        println!("\nValue stream output:");
        println!("  burn: {:.6}", burn_value);
        println!("  fast: {:.6}", fast_value);

        // Compare h1 element by element
        let h1_match = burn_h1_slice.iter().zip(fast_h1.iter())
            .filter(|(a, b)| (*a - *b).abs() < 1e-4).count();
        println!("\nH1 comparison: {}/{} match (within 1e-4)", h1_match, burn_h1_slice.len());

        if h1_match < burn_h1_slice.len() {
            println!("H1 mismatches (first 5):");
            for (i, (a, b)) in burn_h1_slice.iter().zip(fast_h1.iter()).enumerate().take(10) {
                if (a - b).abs() >= 1e-4 {
                    println!("  [{}]: burn={:.6}, fast={:.6}, diff={:.6}", i, a, b, (a - b).abs());
                }
            }
        }

        // Manual computation test for neuron 0
        // Burn computes: output[o] = ReLU(Σ_i W[o,i] * input[i] + bias[o])
        // FastDQN computes: output[o] = ReLU(Σ_i weights[o*in+i] * input[i] + bias[o])
        // Both should be the same if weights are correctly stored as [out, in]
        println!("\n=== MANUAL COMPUTATION TEST FOR NEURON 0 ===");
        let burn_w = burn_shared1_w; // [out, in] format from burn
        let fast_w = fast_internal;  // [out, in] format stored in FastDQN

        // Compute dot product for neuron 0 using burn weights
        let mut burn_sum: f64 = burn_s1_bias[0] as f64;
        for i in 0..FEATURE_DIM {
            let w_idx = 0 * 45 + i;  // burn format: o * in + i
            burn_sum += burn_w[w_idx] as f64 * 0.5;
        }
        let burn_relu = (burn_sum as f32).max(0.0);

        // Compute dot product for neuron 0 using fast weights
        let mut fast_sum: f64 = fast_s1_bias[0] as f64;
        for i in 0..FEATURE_DIM {
            let w_idx = 0 * 45 + i;  // fast format: o * in + i
            fast_sum += fast_w[w_idx] as f64 * 0.5;
        }
        let fast_relu = (fast_sum as f32).max(0.0);

        println!("Burn weights for neuron 0 (first 5): {:?}", &burn_w[0..5]);
        println!("Fast weights for neuron 0 (first 5): {:?}", &fast_w[0..5]);
        println!("Burn bias[0] = {}", burn_s1_bias[0]);
        println!("Fast bias[0] = {}", fast_s1_bias[0]);
        println!("Manual burn sum (before ReLU): {:.6}", burn_sum);
        println!("Manual fast sum (before ReLU): {:.6}", fast_sum);
        println!("Manual burn output[0] (after ReLU): {:.6}", burn_relu);
        println!("Manual fast output[0] (after ReLU): {:.6}", fast_relu);
        println!("Actual burn h1[0]: {:.6}", burn_h1_slice[0]);
        println!("Actual fast h1[0]: {:.6}", fast_h1[0]);

        // TEST HYPOTHESIS: burn might use [in, out] format in computation
        // If burn computes output[o] = Σ_i input[i] * W[i * out_dim + o] + bias[o]
        // where out_dim = 128, then for neuron 0:
        println!("\n=== TESTING BURN INDEXING HYPOTHESIS ===");
        let mut alt_sum: f64 = burn_s1_bias[0] as f64;
        for i in 0..FEATURE_DIM {
            let w_idx = i * 128 + 0;  // [in, out] indexing for output 0
            if w_idx < burn_w.len() {
                alt_sum += burn_w[w_idx] as f64 * 0.5;
            }
        }
        let alt_relu = (alt_sum as f32).max(0.0);
        println!("Alt sum (using [in, out] indexing): {:.6}", alt_sum);
        println!("Alt output (after ReLU): {:.6}", alt_relu);
        println!("Does alt match actual burn? {}", (alt_relu - burn_h1_slice[0]).abs() < 1e-4);

        // Test all decision types
        for dt in DecisionType::all() {
            let q_burn = dqn_burn.forward(input_tensor.clone(), dt);
            let q_burn_data = q_burn.into_data();
            let q_burn_slice = q_burn_data.as_slice::<f32>().unwrap();

            let fast_dt = match dt {
                DecisionType::HandSize => FastDecisionType::HandSize,
                DecisionType::ZapZap => FastDecisionType::ZapZap,
                DecisionType::PlayType => FastDecisionType::PlayType,
                DecisionType::DrawSource => FastDecisionType::DrawSource,
            };
            let q_fast = fast_dqn.predict(&input, fast_dt);

            println!("\nDecision {:?}:", dt);
            println!("  DuelingDQN: {:?}", &q_burn_slice[..dt.action_dim()]);
            println!("  FastDQN:    {:?}", &q_fast[..dt.action_dim()]);

            // Compare Q-values
            for (i, (burn_v, fast_v)) in q_burn_slice.iter().zip(q_fast.iter()).enumerate() {
                let diff = (burn_v - fast_v).abs();
                assert!(
                    diff < 0.01,
                    "Q-value mismatch at {} for {:?}: burn={}, fast={}, diff={}",
                    i, dt, burn_v, fast_v, diff
                );
            }
        }
    }
}
