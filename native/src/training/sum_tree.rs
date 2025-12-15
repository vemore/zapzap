//! SumTree data structure for O(log n) prioritized sampling

/// SumTree for efficient prioritized sampling
///
/// A binary tree where each parent node stores the sum of its children.
/// Allows O(log n) sampling based on priorities and O(log n) updates.
pub struct SumTree {
    /// Capacity (number of leaf nodes)
    capacity: usize,
    /// Binary tree stored as array: parent nodes followed by leaf nodes
    /// Total size = 2 * capacity - 1
    tree: Vec<f32>,
    /// Current write position (circular buffer)
    write_position: usize,
    /// Number of elements currently stored
    size: usize,
}

impl SumTree {
    /// Create a new SumTree with given capacity
    pub fn new(capacity: usize) -> Self {
        let tree_size = 2 * capacity - 1;
        Self {
            capacity,
            tree: vec![0.0; tree_size],
            write_position: 0,
            size: 0,
        }
    }

    /// Get the total sum of all priorities
    #[inline]
    pub fn total(&self) -> f32 {
        self.tree[0]
    }

    /// Get minimum priority among leaf nodes
    pub fn min_priority(&self) -> f32 {
        let leaf_start = self.capacity - 1;
        self.tree[leaf_start..leaf_start + self.size]
            .iter()
            .cloned()
            .filter(|&p| p > 0.0)
            .fold(f32::MAX, f32::min)
    }

    /// Get current size
    #[inline]
    pub fn len(&self) -> usize {
        self.size
    }

    /// Check if empty
    #[inline]
    pub fn is_empty(&self) -> bool {
        self.size == 0
    }

    /// Add a new priority, returns the data index
    pub fn add(&mut self, priority: f32) -> usize {
        let data_idx = self.write_position;
        let tree_idx = self.write_position + self.capacity - 1;

        // Update tree
        self.update_internal(tree_idx, priority);

        // Move write position
        self.write_position = (self.write_position + 1) % self.capacity;
        self.size = (self.size + 1).min(self.capacity);

        data_idx
    }

    /// Update priority at given data index
    pub fn update(&mut self, data_idx: usize, priority: f32) {
        let tree_idx = data_idx + self.capacity - 1;
        self.update_internal(tree_idx, priority);
    }

    /// Internal update: set tree[tree_idx] = priority and propagate up
    fn update_internal(&mut self, tree_idx: usize, priority: f32) {
        let change = priority - self.tree[tree_idx];
        self.tree[tree_idx] = priority;

        // Propagate change up to root
        let mut idx = tree_idx;
        while idx > 0 {
            idx = (idx - 1) / 2;
            self.tree[idx] += change;
        }
    }

    /// Sample an index given a random value in [0, total)
    ///
    /// Returns (data_index, priority)
    pub fn get(&self, value: f32) -> (usize, f32) {
        let mut idx = 0;
        let mut remaining = value;

        loop {
            let left = 2 * idx + 1;
            let right = left + 1;

            // If we've reached a leaf node
            if left >= self.tree.len() {
                break;
            }

            // Go left or right based on remaining value
            if remaining <= self.tree[left] {
                idx = left;
            } else {
                remaining -= self.tree[left];
                idx = right;
            }
        }

        let data_idx = idx - (self.capacity - 1);
        (data_idx, self.tree[idx])
    }

    /// Get priority at data index
    pub fn get_priority(&self, data_idx: usize) -> f32 {
        self.tree[data_idx + self.capacity - 1]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new() {
        let tree = SumTree::new(8);
        assert_eq!(tree.capacity, 8);
        assert_eq!(tree.tree.len(), 15); // 2*8 - 1
        assert_eq!(tree.total(), 0.0);
        assert!(tree.is_empty());
    }

    #[test]
    fn test_add_and_total() {
        let mut tree = SumTree::new(4);

        tree.add(1.0);
        assert_eq!(tree.total(), 1.0);
        assert_eq!(tree.len(), 1);

        tree.add(2.0);
        assert_eq!(tree.total(), 3.0);
        assert_eq!(tree.len(), 2);

        tree.add(3.0);
        tree.add(4.0);
        assert_eq!(tree.total(), 10.0);
        assert_eq!(tree.len(), 4);
    }

    #[test]
    fn test_circular_buffer() {
        let mut tree = SumTree::new(4);

        // Fill buffer
        tree.add(1.0);
        tree.add(2.0);
        tree.add(3.0);
        tree.add(4.0);
        assert_eq!(tree.total(), 10.0);

        // Overflow - should replace first element
        tree.add(5.0);
        assert_eq!(tree.total(), 14.0); // 5 + 2 + 3 + 4
        assert_eq!(tree.len(), 4); // Still at capacity
    }

    #[test]
    fn test_update() {
        let mut tree = SumTree::new(4);

        tree.add(1.0);
        tree.add(2.0);
        tree.add(3.0);
        assert_eq!(tree.total(), 6.0);

        // Update second element
        tree.update(1, 5.0);
        assert_eq!(tree.total(), 9.0); // 1 + 5 + 3
    }

    #[test]
    fn test_get_sampling() {
        let mut tree = SumTree::new(4);

        tree.add(1.0); // idx 0
        tree.add(2.0); // idx 1
        tree.add(3.0); // idx 2
        tree.add(4.0); // idx 3
        // Total = 10

        // Sample from different ranges
        let (idx, _) = tree.get(0.5); // Should be in first segment
        assert_eq!(idx, 0);

        let (idx, _) = tree.get(1.5); // Should be in second segment
        assert_eq!(idx, 1);

        let (idx, _) = tree.get(4.0); // Should be in third segment
        assert_eq!(idx, 2);

        let (idx, _) = tree.get(7.0); // Should be in fourth segment
        assert_eq!(idx, 3);
    }

    #[test]
    fn test_get_priority() {
        let mut tree = SumTree::new(4);

        tree.add(1.5);
        tree.add(2.5);

        assert_eq!(tree.get_priority(0), 1.5);
        assert_eq!(tree.get_priority(1), 2.5);
    }

    #[test]
    fn test_min_priority() {
        let mut tree = SumTree::new(4);

        tree.add(3.0);
        tree.add(1.0);
        tree.add(5.0);

        assert_eq!(tree.min_priority(), 1.0);
    }
}
