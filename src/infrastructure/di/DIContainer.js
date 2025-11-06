/**
 * Dependency Injection Container
 * Simple DI container for managing dependencies
 */

class DIContainer {
    constructor() {
        this.services = new Map();
        this.singletons = new Map();
    }

    /**
     * Register a service or singleton instance
     * @param {string} name - Service name
     * @param {*} service - Service instance or factory function
     * @param {boolean} singleton - Whether to treat as singleton (default: true)
     */
    register(name, service, singleton = true) {
        if (singleton) {
            this.singletons.set(name, service);
        } else {
            this.services.set(name, service);
        }
    }

    /**
     * Resolve a service by name
     * @param {string} name - Service name
     * @returns {*} Service instance
     */
    resolve(name) {
        // Check singletons first
        if (this.singletons.has(name)) {
            return this.singletons.get(name);
        }

        // Check services
        if (this.services.has(name)) {
            const service = this.services.get(name);
            // If it's a factory function, call it
            return typeof service === 'function' ? service() : service;
        }

        throw new Error(`Service '${name}' not found in container`);
    }

    /**
     * Check if a service is registered
     * @param {string} name - Service name
     * @returns {boolean}
     */
    has(name) {
        return this.singletons.has(name) || this.services.has(name);
    }

    /**
     * Remove a service from the container
     * @param {string} name - Service name
     */
    unregister(name) {
        this.singletons.delete(name);
        this.services.delete(name);
    }

    /**
     * Clear all services
     */
    clear() {
        this.services.clear();
        this.singletons.clear();
    }

    /**
     * Get all registered service names
     * @returns {string[]}
     */
    getServiceNames() {
        return [
            ...Array.from(this.singletons.keys()),
            ...Array.from(this.services.keys())
        ];
    }
}

module.exports = DIContainer;
