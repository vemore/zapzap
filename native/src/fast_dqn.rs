//! FastDQN - Optimized Dueling DQN for high-speed inference
//!
//! Architecture matches DuelingDQN (burn) for weight synchronization:
//! - Shared layers: 45 → 128 → 64
//! - Value stream: 64 → 32 → 1
//! - Advantage heads (4): 64 → 32 → [7, 2, 5, 2]
//!
//! Q(s,a) = V(s) + (A(s,a) - mean(A(s,:)))
//!
//! Optimizations:
//! - Flat weight arrays for cache locality
//! - Pre-allocated activation buffers
//! - No allocations during inference

use crate::feature_extractor::FEATURE_DIM;

/// Decision types with their action dimensions
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DecisionType {
    HandSize,   // 7 actions (4-10 cards)
    ZapZap,     // 2 actions (no, yes)
    PlayType,   // 5 actions (different play strategies)
    DrawSource, // 2 actions (deck, discard)
}

impl DecisionType {
    #[inline]
    pub fn action_dim(&self) -> usize {
        match self {
            DecisionType::HandSize => 7,
            DecisionType::ZapZap => 2,
            DecisionType::PlayType => 5,
            DecisionType::DrawSource => 2,
        }
    }

    pub fn all() -> &'static [DecisionType] {
        &[
            DecisionType::HandSize,
            DecisionType::ZapZap,
            DecisionType::PlayType,
            DecisionType::DrawSource,
        ]
    }

    pub fn from_u8(v: u8) -> Option<DecisionType> {
        match v {
            0 => Some(DecisionType::HandSize),
            1 => Some(DecisionType::ZapZap),
            2 => Some(DecisionType::PlayType),
            3 => Some(DecisionType::DrawSource),
            _ => None,
        }
    }
}

/// Layer dimensions matching DuelingDQN (burn)
const HIDDEN1: usize = 128;  // shared1 output
const HIDDEN2: usize = 64;   // shared2 output (also input to value & advantage)
const ADV_HIDDEN: usize = 32; // advantage/value hidden
const MAX_ACTIONS: usize = 7;

// Weight array sizes for shared layers
const W1_SIZE: usize = FEATURE_DIM * HIDDEN1; // 45 * 128 = 5760
const W2_SIZE: usize = HIDDEN1 * HIDDEN2;     // 128 * 64 = 8192

// Value stream weights
const V1_SIZE: usize = HIDDEN2 * ADV_HIDDEN;  // 64 * 32 = 2048
const V2_SIZE: usize = ADV_HIDDEN * 1;        // 32 * 1 = 32

// Advantage head weights (per head)
const A1_SIZE: usize = HIDDEN2 * ADV_HIDDEN;  // 64 * 32 = 2048
const A2_MAX_SIZE: usize = ADV_HIDDEN * MAX_ACTIONS; // 32 * 7 = 224

/// Shared layer 1: 45 -> 128
#[derive(Clone)]
struct SharedLayer1 {
    weights: [f32; W1_SIZE],
    bias: [f32; HIDDEN1],
}

impl SharedLayer1 {
    fn new_random(seed: u64) -> Self {
        let scale = (2.0 / FEATURE_DIM as f32).sqrt();
        let mut rng = seed;

        let mut weights = [0.0f32; W1_SIZE];
        for w in weights.iter_mut() {
            rng ^= rng << 13;
            rng ^= rng >> 7;
            rng ^= rng << 17;
            let r = (rng as f32 / u64::MAX as f32) * 2.0 - 1.0;
            *w = r * scale;
        }

        Self {
            weights,
            bias: [0.0; HIDDEN1],
        }
    }

    #[inline(always)]
    fn forward_relu(&self, input: &[f32; FEATURE_DIM], output: &mut [f32; HIDDEN1]) {
        for o in 0..HIDDEN1 {
            let mut sum = self.bias[o];
            let base = o * FEATURE_DIM;
            for i in 0..FEATURE_DIM {
                sum += self.weights[base + i] * input[i];
            }
            output[o] = sum.max(0.0);
        }
    }

    /// Set weights from burn format [out, in] (direct copy, no transposition needed)
    fn set_weights(&mut self, flat_weights: &[f32], flat_bias: &[f32]) {
        // Burn exports in [out, in] format, same as our internal format
        let copy_len = flat_weights.len().min(W1_SIZE);
        self.weights[..copy_len].copy_from_slice(&flat_weights[..copy_len]);

        let bias_copy_len = flat_bias.len().min(HIDDEN1);
        self.bias[..bias_copy_len].copy_from_slice(&flat_bias[..bias_copy_len]);
    }

    fn get_weights(&self) -> (&[f32], &[f32]) {
        (&self.weights, &self.bias)
    }
}

/// Shared layer 2: 128 -> 64
#[derive(Clone)]
struct SharedLayer2 {
    weights: [f32; W2_SIZE],
    bias: [f32; HIDDEN2],
}

impl SharedLayer2 {
    fn new_random(seed: u64) -> Self {
        let scale = (2.0 / HIDDEN1 as f32).sqrt();
        let mut rng = seed;

        let mut weights = [0.0f32; W2_SIZE];
        for w in weights.iter_mut() {
            rng ^= rng << 13;
            rng ^= rng >> 7;
            rng ^= rng << 17;
            let r = (rng as f32 / u64::MAX as f32) * 2.0 - 1.0;
            *w = r * scale;
        }

        Self {
            weights,
            bias: [0.0; HIDDEN2],
        }
    }

    #[inline(always)]
    fn forward_relu(&self, input: &[f32; HIDDEN1], output: &mut [f32; HIDDEN2]) {
        for o in 0..HIDDEN2 {
            let mut sum = self.bias[o];
            let base = o * HIDDEN1;
            for i in 0..HIDDEN1 {
                sum += self.weights[base + i] * input[i];
            }
            output[o] = sum.max(0.0);
        }
    }

    /// Set weights from burn format [out, in] (direct copy, no transposition needed)
    fn set_weights(&mut self, flat_weights: &[f32], flat_bias: &[f32]) {
        // Burn exports in [out, in] format, same as our internal format
        let copy_len = flat_weights.len().min(W2_SIZE);
        self.weights[..copy_len].copy_from_slice(&flat_weights[..copy_len]);

        let bias_copy_len = flat_bias.len().min(HIDDEN2);
        self.bias[..bias_copy_len].copy_from_slice(&flat_bias[..bias_copy_len]);
    }

    fn get_weights(&self) -> (&[f32], &[f32]) {
        (&self.weights, &self.bias)
    }
}

/// Value stream: 64 -> 32 -> 1
#[derive(Clone)]
struct ValueStream {
    weights1: [f32; V1_SIZE],
    bias1: [f32; ADV_HIDDEN],
    weights2: [f32; V2_SIZE],
    bias2: f32,
    // Activation buffer
    h: [f32; ADV_HIDDEN],
}

impl ValueStream {
    fn new_random(seed: u64) -> Self {
        let scale1 = (2.0 / HIDDEN2 as f32).sqrt();
        let scale2 = (2.0 / ADV_HIDDEN as f32).sqrt();
        let mut rng = seed;

        let mut weights1 = [0.0f32; V1_SIZE];
        for w in weights1.iter_mut() {
            rng ^= rng << 13;
            rng ^= rng >> 7;
            rng ^= rng << 17;
            let r = (rng as f32 / u64::MAX as f32) * 2.0 - 1.0;
            *w = r * scale1;
        }

        let mut weights2 = [0.0f32; V2_SIZE];
        for w in weights2.iter_mut() {
            rng ^= rng << 13;
            rng ^= rng >> 7;
            rng ^= rng << 17;
            let r = (rng as f32 / u64::MAX as f32) * 2.0 - 1.0;
            *w = r * scale2;
        }

        Self {
            weights1,
            bias1: [0.0; ADV_HIDDEN],
            weights2,
            bias2: 0.0,
            h: [0.0; ADV_HIDDEN],
        }
    }

    #[inline(always)]
    fn forward(&mut self, input: &[f32; HIDDEN2]) -> f32 {
        // Layer 1: 64 -> 32 with ReLU
        for o in 0..ADV_HIDDEN {
            let mut sum = self.bias1[o];
            let base = o * HIDDEN2;
            for i in 0..HIDDEN2 {
                sum += self.weights1[base + i] * input[i];
            }
            self.h[o] = sum.max(0.0);
        }

        // Layer 2: 32 -> 1 (linear)
        let mut value = self.bias2;
        for i in 0..ADV_HIDDEN {
            value += self.weights2[i] * self.h[i];
        }
        value
    }

    /// Set weights from burn format [out, in] (direct copy, no transposition needed)
    fn set_weights(&mut self, w1: &[f32], b1: &[f32], w2: &[f32], b2: f32) {
        // Layer 1: 64 -> 32 (burn exports in [out, in] format)
        let copy_len = w1.len().min(V1_SIZE);
        self.weights1[..copy_len].copy_from_slice(&w1[..copy_len]);

        let bias_copy_len = b1.len().min(ADV_HIDDEN);
        self.bias1[..bias_copy_len].copy_from_slice(&b1[..bias_copy_len]);

        // Layer 2: 32 -> 1 (single output, just copy weights)
        let w2_copy_len = w2.len().min(V2_SIZE);
        self.weights2[..w2_copy_len].copy_from_slice(&w2[..w2_copy_len]);
        self.bias2 = b2;
    }

    fn get_weights(&self) -> (&[f32], &[f32], &[f32], f32) {
        (&self.weights1, &self.bias1, &self.weights2, self.bias2)
    }
}

/// Advantage head: 64 -> 32 -> action_dim
#[derive(Clone)]
struct AdvantageHead {
    weights1: [f32; A1_SIZE],
    bias1: [f32; ADV_HIDDEN],
    weights2: [f32; A2_MAX_SIZE],
    bias2: [f32; MAX_ACTIONS],
    action_dim: usize,
    // Activation buffer
    h: [f32; ADV_HIDDEN],
}

impl AdvantageHead {
    fn new_random(action_dim: usize, seed: u64) -> Self {
        let scale1 = (2.0 / HIDDEN2 as f32).sqrt();
        let scale2 = (2.0 / ADV_HIDDEN as f32).sqrt();
        let mut rng = seed;

        let mut weights1 = [0.0f32; A1_SIZE];
        for w in weights1.iter_mut() {
            rng ^= rng << 13;
            rng ^= rng >> 7;
            rng ^= rng << 17;
            let r = (rng as f32 / u64::MAX as f32) * 2.0 - 1.0;
            *w = r * scale1;
        }

        let mut weights2 = [0.0f32; A2_MAX_SIZE];
        for w in weights2.iter_mut() {
            rng ^= rng << 13;
            rng ^= rng >> 7;
            rng ^= rng << 17;
            let r = (rng as f32 / u64::MAX as f32) * 2.0 - 1.0;
            *w = r * scale2;
        }

        Self {
            weights1,
            bias1: [0.0; ADV_HIDDEN],
            weights2,
            bias2: [0.0; MAX_ACTIONS],
            action_dim,
            h: [0.0; ADV_HIDDEN],
        }
    }

    /// Forward pass returns advantage values
    #[inline(always)]
    fn forward(&mut self, input: &[f32; HIDDEN2], output: &mut [f32]) {
        // Layer 1: 64 -> 32 with ReLU
        for o in 0..ADV_HIDDEN {
            let mut sum = self.bias1[o];
            let base = o * HIDDEN2;
            for i in 0..HIDDEN2 {
                sum += self.weights1[base + i] * input[i];
            }
            self.h[o] = sum.max(0.0);
        }

        // Layer 2: 32 -> action_dim (linear)
        for a in 0..self.action_dim {
            let mut sum = self.bias2[a];
            let base = a * ADV_HIDDEN;
            for i in 0..ADV_HIDDEN {
                sum += self.weights2[base + i] * self.h[i];
            }
            output[a] = sum;
        }
    }

    /// Set weights from burn format [out, in] (direct copy, no transposition needed)
    fn set_weights(&mut self, w1: &[f32], b1: &[f32], w2: &[f32], b2: &[f32]) {
        // Layer 1: 64 -> 32 (burn exports in [out, in] format)
        let copy_len = w1.len().min(A1_SIZE);
        self.weights1[..copy_len].copy_from_slice(&w1[..copy_len]);

        let bias_copy_len = b1.len().min(ADV_HIDDEN);
        self.bias1[..bias_copy_len].copy_from_slice(&b1[..bias_copy_len]);

        // Layer 2: 32 -> action_dim (burn exports in [out, in] = [action_dim, 32] format)
        let w2_copy_len = w2.len().min(self.action_dim * ADV_HIDDEN);
        self.weights2[..w2_copy_len].copy_from_slice(&w2[..w2_copy_len]);

        let b2_copy_len = b2.len().min(self.action_dim);
        self.bias2[..b2_copy_len].copy_from_slice(&b2[..b2_copy_len]);
    }

    fn get_weights(&self) -> (&[f32], &[f32], &[f32], &[f32]) {
        (&self.weights1, &self.bias1, &self.weights2[..self.action_dim * ADV_HIDDEN], &self.bias2[..self.action_dim])
    }
}

/// FastDQN with Dueling architecture matching DuelingDQN (burn)
pub struct FastDQN {
    // Shared layers
    shared1: SharedLayer1,
    shared2: SharedLayer2,

    // Value stream
    value: ValueStream,

    // Advantage heads (one per decision type)
    adv_hand_size: AdvantageHead,
    adv_zapzap: AdvantageHead,
    adv_play_type: AdvantageHead,
    adv_draw_source: AdvantageHead,

    // RNG state
    rng_state: u64,

    // Pre-allocated activation buffers
    h1: [f32; HIDDEN1],
    h2: [f32; HIDDEN2],
    q_values: [f32; MAX_ACTIONS],
}

impl FastDQN {
    /// Create with random weights
    pub fn new() -> Self {
        Self::with_seed(42)
    }

    /// Create with specific seed
    pub fn with_seed(seed: u64) -> Self {
        FastDQN {
            shared1: SharedLayer1::new_random(seed),
            shared2: SharedLayer2::new_random(seed.wrapping_add(1)),
            value: ValueStream::new_random(seed.wrapping_add(2)),
            adv_hand_size: AdvantageHead::new_random(7, seed.wrapping_add(3)),
            adv_zapzap: AdvantageHead::new_random(2, seed.wrapping_add(4)),
            adv_play_type: AdvantageHead::new_random(5, seed.wrapping_add(5)),
            adv_draw_source: AdvantageHead::new_random(2, seed.wrapping_add(6)),
            rng_state: seed,
            h1: [0.0; HIDDEN1],
            h2: [0.0; HIDDEN2],
            q_values: [0.0; MAX_ACTIONS],
        }
    }

    /// Get mutable reference to advantage head for a decision type
    #[inline]
    fn adv_head_mut(&mut self, dt: DecisionType) -> &mut AdvantageHead {
        match dt {
            DecisionType::HandSize => &mut self.adv_hand_size,
            DecisionType::ZapZap => &mut self.adv_zapzap,
            DecisionType::PlayType => &mut self.adv_play_type,
            DecisionType::DrawSource => &mut self.adv_draw_source,
        }
    }

    /// Forward pass through shared layers
    #[inline]
    fn forward_shared(&mut self, input: &[f32; FEATURE_DIM]) {
        self.shared1.forward_relu(input, &mut self.h1);
        self.shared2.forward_relu(&self.h1, &mut self.h2);
    }

    /// Get Q-values for a decision type using dueling architecture
    #[inline]
    pub fn predict(&mut self, input: &[f32; FEATURE_DIM], decision_type: DecisionType) -> &[f32] {
        let action_dim = decision_type.action_dim();

        // Forward through shared layers
        self.forward_shared(input);

        // Value stream - copy h2 to avoid borrow issues
        let h2_copy = self.h2;
        let value = self.value.forward(&h2_copy);

        // Advantage stream for this decision type
        match decision_type {
            DecisionType::HandSize => self.adv_hand_size.forward(&h2_copy, &mut self.q_values),
            DecisionType::ZapZap => self.adv_zapzap.forward(&h2_copy, &mut self.q_values),
            DecisionType::PlayType => self.adv_play_type.forward(&h2_copy, &mut self.q_values),
            DecisionType::DrawSource => self.adv_draw_source.forward(&h2_copy, &mut self.q_values),
        }

        // Compute mean advantage
        let mut adv_sum = 0.0f32;
        for i in 0..action_dim {
            adv_sum += self.q_values[i];
        }
        let adv_mean = adv_sum / action_dim as f32;

        // Q(s,a) = V(s) + (A(s,a) - mean(A))
        for i in 0..action_dim {
            self.q_values[i] = value + self.q_values[i] - adv_mean;
        }

        &self.q_values[..action_dim]
    }

    /// Select action using epsilon-greedy policy
    #[inline]
    pub fn select_action(
        &mut self,
        input: &[f32; FEATURE_DIM],
        decision_type: DecisionType,
        epsilon: f32,
    ) -> usize {
        // Exploration
        if self.random_f32() < epsilon {
            return self.random_action(decision_type);
        }

        // Exploitation - greedy action
        self.greedy_action(input, decision_type)
    }

    /// Select greedy action (best Q-value)
    #[inline]
    pub fn greedy_action(&mut self, input: &[f32; FEATURE_DIM], decision_type: DecisionType) -> usize {
        let q_values = self.predict(input, decision_type);
        let mut best_action = 0;
        let mut best_value = q_values[0];
        for (i, &v) in q_values.iter().enumerate().skip(1) {
            if v > best_value {
                best_value = v;
                best_action = i;
            }
        }
        best_action
    }

    /// Random action for exploration
    fn random_action(&mut self, decision_type: DecisionType) -> usize {
        let action_dim = decision_type.action_dim();
        self.random_range(action_dim)
    }

    /// Simple xorshift64 RNG
    #[inline]
    fn next_random(&mut self) -> u64 {
        let mut x = self.rng_state;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.rng_state = x;
        x
    }

    #[inline]
    fn random_f32(&mut self) -> f32 {
        self.next_random() as f32 / u64::MAX as f32
    }

    #[inline]
    fn random_range(&mut self, max: usize) -> usize {
        if max == 0 { return 0; }
        (self.next_random() % max as u64) as usize
    }

    /// Get internal shared1 weights (stored as [out, in]) for debugging
    pub fn get_shared1_internal_weights(&self) -> Vec<f32> {
        self.shared1.weights.to_vec()
    }

    /// Get all layer weights for debugging (all in internal [out, in] format)
    /// Returns: (shared2, value1, value2, adv_hand_size_l1, adv_hand_size_l2)
    pub fn get_all_layer_weights(&self) -> (Vec<f32>, Vec<f32>, Vec<f32>, Vec<f32>, Vec<f32>) {
        let s2 = self.shared2.weights.to_vec();
        let v1 = self.value.weights1.to_vec();
        let v2 = self.value.weights2.to_vec();
        let ahs1 = self.adv_hand_size.weights1.to_vec();
        let ahs2 = self.adv_hand_size.weights2[..self.adv_hand_size.action_dim * ADV_HIDDEN].to_vec();
        (s2, v1, v2, ahs1, ahs2)
    }

    /// Get all biases for debugging
    /// Returns: (s1_bias, s2_bias, v1_bias, v2_bias, ahs1_bias, ahs2_bias)
    pub fn get_all_biases(&self) -> (Vec<f32>, Vec<f32>, Vec<f32>, f32, Vec<f32>, Vec<f32>) {
        let s1_bias = self.shared1.bias.to_vec();
        let s2_bias = self.shared2.bias.to_vec();
        let v1_bias = self.value.bias1.to_vec();
        let v2_bias = self.value.bias2;
        let ahs1_bias = self.adv_hand_size.bias1.to_vec();
        let ahs2_bias = self.adv_hand_size.bias2[..self.adv_hand_size.action_dim].to_vec();
        (s1_bias, s2_bias, v1_bias, v2_bias, ahs1_bias, ahs2_bias)
    }

    /// Debug forward pass returning intermediate activations
    /// Returns: (h1: [128], h2: [64], value: scalar)
    pub fn forward_debug(&mut self, input: &[f32; FEATURE_DIM]) -> (Vec<f32>, Vec<f32>, f32) {
        // Shared layer 1
        self.shared1.forward_relu(input, &mut self.h1);
        let h1_out = self.h1.to_vec();

        // Shared layer 2
        self.shared2.forward_relu(&self.h1, &mut self.h2);
        let h2_out = self.h2.to_vec();

        // Value stream
        let h2_copy = self.h2;
        let value = self.value.forward(&h2_copy);

        (h1_out, h2_out, value)
    }

    /// Get all weights as flat vector for serialization
    /// Format: [out, in] - same as internal storage and DuelingDQN.get_weights_flat() output
    /// This allows direct round-trip with set_weights_flat()
    pub fn get_weights_flat(&self) -> Vec<f32> {
        let mut weights = Vec::with_capacity(40000);

        // Shared1 weights (45*128 + 128) - already in [out, in] format
        let (w, b) = self.shared1.get_weights();
        weights.extend_from_slice(w);
        weights.extend_from_slice(b);

        // Shared2 weights (128*64 + 64)
        let (w, b) = self.shared2.get_weights();
        weights.extend_from_slice(w);
        weights.extend_from_slice(b);

        // Value stream layer1 (64*32 + 32)
        let (w1, b1, w2, b2) = self.value.get_weights();
        weights.extend_from_slice(w1);
        weights.extend_from_slice(b1);

        // Value stream layer2 (32*1 + 1)
        weights.extend_from_slice(w2);
        weights.push(b2);

        // Advantage heads in order: hand_size, zapzap, play_type, draw_source
        for (head, action_dim) in [
            (&self.adv_hand_size, 7),
            (&self.adv_zapzap, 2),
            (&self.adv_play_type, 5),
            (&self.adv_draw_source, 2),
        ] {
            let (w1, b1, w2, b2) = head.get_weights();

            // Layer1 (64*32 + 32)
            weights.extend_from_slice(w1);
            weights.extend_from_slice(b1);

            // Layer2 (32*action_dim + action_dim)
            weights.extend_from_slice(&w2[..ADV_HIDDEN * action_dim]);
            weights.extend_from_slice(&b2[..action_dim]);
        }

        weights
    }

    /// Set weights from flat vector (from get_weights_flat or DuelingDQN training)
    /// Input format is already [out, in] (DuelingDQN.get_weights_flat() pre-transposes)
    /// This matches FastDQN's internal storage format, so NO transposition needed
    pub fn set_weights_flat(&mut self, weights: &[f32]) {
        if weights.is_empty() {
            return;
        }

        let mut idx = 0usize;

        // Helper to get slice and advance index
        fn take_slice<'a>(weights: &'a [f32], idx: &mut usize, count: usize) -> &'a [f32] {
            let start = *idx;
            let end = (start + count).min(weights.len());
            *idx = start + count;
            &weights[start..end]
        }

        // Shared1 (45*128 weights + 128 bias) - weights arrive in [out, in] format
        let w1_size = FEATURE_DIM * HIDDEN1;
        let s1_w = take_slice(weights, &mut idx, w1_size);
        let s1_b = take_slice(weights, &mut idx, HIDDEN1);
        self.shared1.set_weights(s1_w, s1_b);

        // Shared2 (128*64 weights + 64 bias)
        let w2_size = HIDDEN1 * HIDDEN2;
        let s2_w = take_slice(weights, &mut idx, w2_size);
        let s2_b = take_slice(weights, &mut idx, HIDDEN2);
        self.shared2.set_weights(s2_w, s2_b);

        // Value stream layer1 (64*32 + 32)
        let v1_w = take_slice(weights, &mut idx, HIDDEN2 * ADV_HIDDEN);
        let v1_b = take_slice(weights, &mut idx, ADV_HIDDEN);
        // Value stream layer2 (32*1 + 1)
        let v2_w = take_slice(weights, &mut idx, ADV_HIDDEN);
        let v2_b = if idx < weights.len() { weights[idx] } else { 0.0 };
        idx += 1;
        self.value.set_weights(v1_w, v1_b, v2_w, v2_b);

        // Advantage heads
        let action_dims = [7usize, 2, 5, 2];

        // HandSize
        let a1_w = take_slice(weights, &mut idx, HIDDEN2 * ADV_HIDDEN);
        let a1_b = take_slice(weights, &mut idx, ADV_HIDDEN);
        let a2_w = take_slice(weights, &mut idx, ADV_HIDDEN * action_dims[0]);
        let a2_b = take_slice(weights, &mut idx, action_dims[0]);
        self.adv_hand_size.set_weights(a1_w, a1_b, a2_w, a2_b);

        // ZapZap
        let a1_w = take_slice(weights, &mut idx, HIDDEN2 * ADV_HIDDEN);
        let a1_b = take_slice(weights, &mut idx, ADV_HIDDEN);
        let a2_w = take_slice(weights, &mut idx, ADV_HIDDEN * action_dims[1]);
        let a2_b = take_slice(weights, &mut idx, action_dims[1]);
        self.adv_zapzap.set_weights(a1_w, a1_b, a2_w, a2_b);

        // PlayType
        let a1_w = take_slice(weights, &mut idx, HIDDEN2 * ADV_HIDDEN);
        let a1_b = take_slice(weights, &mut idx, ADV_HIDDEN);
        let a2_w = take_slice(weights, &mut idx, ADV_HIDDEN * action_dims[2]);
        let a2_b = take_slice(weights, &mut idx, action_dims[2]);
        self.adv_play_type.set_weights(a1_w, a1_b, a2_w, a2_b);

        // DrawSource
        let a1_w = take_slice(weights, &mut idx, HIDDEN2 * ADV_HIDDEN);
        let a1_b = take_slice(weights, &mut idx, ADV_HIDDEN);
        let a2_w = take_slice(weights, &mut idx, ADV_HIDDEN * action_dims[3]);
        let a2_b = take_slice(weights, &mut idx, action_dims[3]);
        self.adv_draw_source.set_weights(a1_w, a1_b, a2_w, a2_b);
    }
}

impl Default for FastDQN {
    fn default() -> Self {
        Self::new()
    }
}

impl Clone for FastDQN {
    fn clone(&self) -> Self {
        FastDQN {
            shared1: self.shared1.clone(),
            shared2: self.shared2.clone(),
            value: self.value.clone(),
            adv_hand_size: self.adv_hand_size.clone(),
            adv_zapzap: self.adv_zapzap.clone(),
            adv_play_type: self.adv_play_type.clone(),
            adv_draw_source: self.adv_draw_source.clone(),
            rng_state: self.rng_state,
            h1: [0.0; HIDDEN1],
            h2: [0.0; HIDDEN2],
            q_values: [0.0; MAX_ACTIONS],
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_decision_types() {
        assert_eq!(DecisionType::HandSize.action_dim(), 7);
        assert_eq!(DecisionType::ZapZap.action_dim(), 2);
        assert_eq!(DecisionType::PlayType.action_dim(), 5);
        assert_eq!(DecisionType::DrawSource.action_dim(), 2);
    }

    #[test]
    fn test_predict() {
        let mut dqn = FastDQN::new();
        let input = [0.5f32; FEATURE_DIM];

        for dt in DecisionType::all() {
            let q_values = dqn.predict(&input, *dt);
            assert_eq!(q_values.len(), dt.action_dim());
        }
    }

    #[test]
    fn test_greedy_action() {
        let mut dqn = FastDQN::with_seed(42);
        let input = [0.5f32; FEATURE_DIM];

        // Greedy should be deterministic with same weights and input
        let action1 = dqn.greedy_action(&input, DecisionType::PlayType);
        let action2 = dqn.greedy_action(&input, DecisionType::PlayType);
        assert_eq!(action1, action2);
        assert!(action1 < DecisionType::PlayType.action_dim());
    }

    #[test]
    fn test_select_action_exploration() {
        let mut dqn = FastDQN::with_seed(42);
        let input = [0.5f32; FEATURE_DIM];

        // With epsilon=1.0, should always explore (random)
        let mut actions = std::collections::HashSet::new();
        for _ in 0..100 {
            let action = dqn.select_action(&input, DecisionType::PlayType, 1.0);
            actions.insert(action);
        }
        // Should have multiple different actions
        assert!(actions.len() > 1);
    }

    #[test]
    fn test_weights_roundtrip() {
        let dqn1 = FastDQN::with_seed(123);
        let weights = dqn1.get_weights_flat();

        // Should have substantial weights
        assert!(weights.len() > 10000);

        let mut dqn2 = FastDQN::with_seed(999);
        dqn2.set_weights_flat(&weights);

        // After setting weights, should produce same outputs
        let input = [0.5f32; FEATURE_DIM];
        let mut dqn1_clone = dqn1.clone();
        let q1 = dqn1_clone.predict(&input, DecisionType::PlayType).to_vec();
        let q2 = dqn2.predict(&input, DecisionType::PlayType).to_vec();

        for (a, b) in q1.iter().zip(q2.iter()) {
            assert!((a - b).abs() < 1e-5, "Q-values differ: {} vs {}", a, b);
        }
    }

    #[test]
    fn test_dueling_output() {
        let mut dqn = FastDQN::with_seed(42);
        let input = [0.5f32; FEATURE_DIM];

        // Q-values should be reasonable (not all zeros)
        let q_values = dqn.predict(&input, DecisionType::HandSize);
        let sum: f32 = q_values.iter().map(|x| x.abs()).sum();
        assert!(sum > 0.0, "Q-values should not all be zero");
    }

    #[test]
    fn test_clone() {
        let dqn1 = FastDQN::with_seed(42);
        let dqn2 = dqn1.clone();

        let input = [0.5f32; FEATURE_DIM];
        let mut dqn1_mut = dqn1.clone();
        let mut dqn2_mut = dqn2;

        let q1 = dqn1_mut.predict(&input, DecisionType::ZapZap).to_vec();
        let q2 = dqn2_mut.predict(&input, DecisionType::ZapZap).to_vec();

        for (a, b) in q1.iter().zip(q2.iter()) {
            assert!((a - b).abs() < 1e-6);
        }
    }
}
