/**
 * ModelStorage
 * Persists and loads ML model weights to/from SQLite database
 */

const fs = require('fs');
const path = require('path');

class ModelStorage {
    /**
     * @param {Object} db - Database connection (optional)
     * @param {string} dataDir - Directory for file-based storage (default: ./data)
     */
    constructor(db = null, dataDir = './data') {
        this.db = db;
        this.dataDir = dataDir;

        // Ensure data directory exists
        if (!fs.existsSync(dataDir)) {
            fs.mkdirSync(dataDir, { recursive: true });
        }
    }

    /**
     * Save policy weights to file
     * @param {string} modelId - Unique model identifier
     * @param {Object} weights - Policy Q-values (from policy.toJSON())
     * @param {Object} metadata - Training metadata
     */
    async save(modelId, weights, metadata = {}) {
        const filePath = this._getFilePath(modelId);
        const data = {
            modelId,
            weights,
            metadata: {
                ...metadata,
                savedAt: Date.now()
            }
        };

        fs.writeFileSync(filePath, JSON.stringify(data, null, 2));

        // Also save to database if available
        if (this.db) {
            await this._saveToDb(modelId, data);
        }

        return { success: true, path: filePath };
    }

    /**
     * Load policy weights from file
     * @param {string} modelId - Model identifier
     * @returns {Object|null} Loaded data or null if not found
     */
    async load(modelId) {
        const filePath = this._getFilePath(modelId);

        if (fs.existsSync(filePath)) {
            const content = fs.readFileSync(filePath, 'utf8');
            return JSON.parse(content);
        }

        // Try database if file not found
        if (this.db) {
            return await this._loadFromDb(modelId);
        }

        return null;
    }

    /**
     * List all saved models
     * @returns {Array<Object>} Model metadata
     */
    async listModels() {
        const models = [];

        // List files
        const files = fs.readdirSync(this.dataDir)
            .filter(f => f.startsWith('ml_model_') && f.endsWith('.json'));

        for (const file of files) {
            const filePath = path.join(this.dataDir, file);
            try {
                const content = fs.readFileSync(filePath, 'utf8');
                const data = JSON.parse(content);
                models.push({
                    modelId: data.modelId,
                    metadata: data.metadata,
                    path: filePath
                });
            } catch (e) {
                // Skip invalid files
            }
        }

        return models;
    }

    /**
     * Delete a model
     * @param {string} modelId
     */
    async delete(modelId) {
        const filePath = this._getFilePath(modelId);

        if (fs.existsSync(filePath)) {
            fs.unlinkSync(filePath);
        }

        if (this.db) {
            await this._deleteFromDb(modelId);
        }

        return { success: true };
    }

    /**
     * Export model to a portable format
     * @param {string} modelId
     * @returns {string} JSON string
     */
    async export(modelId) {
        const data = await this.load(modelId);
        if (!data) {
            throw new Error(`Model ${modelId} not found`);
        }
        return JSON.stringify(data);
    }

    /**
     * Import model from JSON string
     * @param {string} jsonString
     * @returns {Object}
     */
    async import(jsonString) {
        const data = JSON.parse(jsonString);
        if (!data.modelId || !data.weights) {
            throw new Error('Invalid model format');
        }
        await this.save(data.modelId, data.weights, data.metadata);
        return data;
    }

    /**
     * Get file path for a model
     */
    _getFilePath(modelId) {
        const safeId = modelId.replace(/[^a-zA-Z0-9_-]/g, '_');
        return path.join(this.dataDir, `ml_model_${safeId}.json`);
    }

    /**
     * Save to database
     */
    async _saveToDb(modelId, data) {
        if (!this.db) return;

        try {
            const stmt = `
                INSERT OR REPLACE INTO ml_models (model_id, weights_json, metadata_json, games_trained, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
            `;
            const now = Date.now();
            const gamesT = data.metadata?.gamesPlayed || data.weights?.totalUpdates || 0;

            await this.db.run(stmt, [
                modelId,
                JSON.stringify(data.weights),
                JSON.stringify(data.metadata),
                gamesT,
                data.metadata?.createdAt || now,
                now
            ]);
        } catch (e) {
            // Table might not exist - ignore
            console.warn('Could not save to database:', e.message);
        }
    }

    /**
     * Load from database
     */
    async _loadFromDb(modelId) {
        if (!this.db) return null;

        try {
            const row = await this.db.get(
                'SELECT * FROM ml_models WHERE model_id = ?',
                [modelId]
            );

            if (row) {
                return {
                    modelId: row.model_id,
                    weights: JSON.parse(row.weights_json),
                    metadata: JSON.parse(row.metadata_json || '{}')
                };
            }
        } catch (e) {
            // Table might not exist
        }

        return null;
    }

    /**
     * Delete from database
     */
    async _deleteFromDb(modelId) {
        if (!this.db) return;

        try {
            await this.db.run('DELETE FROM ml_models WHERE model_id = ?', [modelId]);
        } catch (e) {
            // Ignore
        }
    }
}

module.exports = ModelStorage;
