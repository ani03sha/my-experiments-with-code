const express = require('express');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 3000;

// Configuration from environment
const CACHE_MODE = process.env.CACHE || 'off';
const CACHE_TTL = parseInt(process.env.CACHE_TTL || '2000', 10);
const DB_URL = process.env.DB_URL || 'http://localhost:3001';

// Metrics
let metrics = {
    cache_hits: 0,
    cache_misses: 0,
    downstream_calls: 0,
    api_queue: 0,
    request_durations: [],
};

// Cache storage
const cache = new Map();
const pendingRequests = new Map(); // For singleflight pattern

// Per-key lock for singleflight
class KeyLock {
    constructor() {
        this.locks = new Map();
        this.waiters = new Map();
    }

    async acquire(key) {
        if (!this.locks.has(key)) {
            this.locks.set(key, 0);
            this.waiters.set(key, []);
        }

        if (this.locks.get(key) === 0) {
            this.locks.set(key, 1);
            return;
        }

        return new Promise((resolve) => {
            this.waiters.get(key).push(resolve);
        });
    }

    release(key) {
        const waiters = this.waiters.get(key);
        if (waiters && waiters.length > 0) {
            const next = waiters.shift();
            next();
        } else {
            this.locks.set(key, 0);
        }
    }
}

const keyLock = new KeyLock();

// Cache entry with expiry
class CacheEntry {
    constructor(value, ttl, isError = false) {
        this.value = value;
        this.expiresAt = Date.now() + ttl;
        this.isError = isError;
    }

    get isValid() {
        return Date.now() < this.expiresAt;
    }
}

// Fetch item from downstream with retry
async function fetchFromDownstream(key) {
    metrics.downstream_calls++;
    try {
        const response = await axios.get(`${DB_URL}/item/${key}`);
        return { data: response.data, error: null };
    } catch (error) {
        return { data: null, error: error.response?.data?.error || error.message };
    }
}

// Naive cache implementation
async function getItemNaive(key) {
    const cached = cache.get(key);
    if (cached && cached.isValid) {
        metrics.cache_hits++;
        if (cached.isError) {
            throw new Error(cached.value)
        }
        return cached.value;
    }
    metrics.cache_misses++;
    const result = await fetchFromDownstream(key);

    if (result.error) {
        throw new Error(result.error);
    }

    cache.set(key, new CacheEntry(result.data, CACHE_TTL));
    return result.data;
}

// Singleflight cache implementation
async function getItemSingleflight(key) {
    const cached = cache.get(key);
    if (cached && cached.isValid) {
        metrics.cache_hits++;
        if (cached.isError) {
            throw new Error(cached.value);
        }
        return cached.value;
    }
    // Check if someone else is also fetching this key
    if (pendingRequests.has(key)) {
        return pendingRequests.get(key);
    }

    metrics.cache_misses++;
    const fetchPromise = fetchFromDownstream(key);
    pendingRequests.set(key, fetchPromise);

    try {
        const result = await fetchPromise;

        if (result.error) {
            const ttl = CACHE_MODE === 'negative' ? 1000 : 0; // Short ttl for errors
            if (ttl > 0) {
                cache.set(key, new CacheEntry(result.error, ttl, true));
            }
            throw new Error(result.error);
        }

        cache.set(key, new CacheEntry(result.data, CACHE_TTL));
        return result.data;
    } finally {
        pendingRequests.delete(key);
    }
}

// Negative cache implementation
async function getItemNegative(key) {
    const cached = cache.get(key);
    if (cached && cached.isValid) {
        metrics.cache_hits++;
        if (cached.isError) {
            throw new Error(cached.value);
        }
        return cached.value;
    }

    await keyLock.acquire(key);

    try {
        // Double-check cache after acquiring lock
        const cachedAgain = cache.get(key);
        if (cachedAgain && cachedAgain.isValid) {
            metrics.cache_hits++;
            if (cachedAgain.isError) {
                throw new Error(cachedAgain.value);
            }
            return cachedAgain.value;
        }

        metrics.cache_misses++;
        const result = await fetchFromDownstream(key);

        if (result.error) {
            // Cache negative result with shorter ttl
            cache.set(key, new CacheEntry(result.error, 1000, true));
            throw new Error(result.error);
        }

        cache.set(key, new CacheEntry(result.data, CACHE_TTL));
        return result.data;
    } finally {
        keyLock.release(key);
    }
}

// Main endpoint
app.get('/item/:id', async (req, res) => {
    metrics.api_queue++;
    const startTime = Date.now();
    const key = req.params.id;

    try {
        let result;
        switch (CACHE_MODE) {
            case 'off':
                const dbResult = await fetchFromDownstream(key);
                if (dbResult.error) {
                    throw new Error(dbResult.error);
                }
                result = dbResult.data;
                break;

            case 'naive':
                result = await getItemNaive(key);
                break;

            case 'singleflight':
                result = await getItemSingleflight(key);
                break;

            case 'negative':
                result = await getItemNegative(key);
                break;

            default:
                throw new Error(`Unknown cache mode: ${CACHE_MODE}`);
        }
        res.json(result);
    } catch (error) {
        res.status(500).json({ error: error.message });
    } finally {
        metrics.api_queue--;
        metrics.request_durations.push(Date.now() - startTime);
        // Keep only last 1000 durations for metrics
        if (metrics.request_durations.length > 1000) {
            metrics.request_durations.shift();
        }
    }
});

// Metrics endpoint
app.get('/metrics', (req, res) => {
    const durations = [...metrics.request_durations].sort((a, b) => a - b);
    const count = durations.length;

    const p50 = count > 0 ? durations[Math.floor(count * 0.5)] : 0;
    const p95 = count > 0 ? durations[Math.floor(count * 0.95)] : 0;
    const p99 = count > 0 ? durations[Math.floor(count * 0.99)] : 0;

    res.set('Content-Type', 'text/plain');
    res.send(`
# HELP cache_hits Total cache hits
# TYPE cache_hits counter
cache_hits ${metrics.cache_hits}

# HELP cache_misses Total cache misses
# TYPE cache_misses counter
cache_misses ${metrics.cache_misses}

# HELP downstream_calls Total downstream calls
# TYPE downstream_calls counter
downstream_calls ${metrics.downstream_calls}

# HELP api_queue Current API queue length
# TYPE api_queue gauge
api_queue ${metrics.api_queue}

# HELP p50_latency_ms 50th percentile latency
# TYPE p50_latency_ms gauge
p50_latency_ms ${p50}

# HELP p95_latency_ms 95th percentile latency
# TYPE p95_latency_ms gauge
p95_latency_ms ${p95}

# HELP p99_latency_ms 99th percentile latency
# TYPE p99_latency_ms gauge
p99_latency_ms ${p99}

# HELP in_flight_loads Pending requests per key (singleflight)
# TYPE in_flight_loads gauge
in_flight_loads ${pendingRequests.size}
`);
});

// Reset cache endpoint (for stampede test)
app.post('/reset_cache', (req, res) => {
    cache.clear();
    pendingRequests.clear();
    metrics = {
        cache_hits: 0,
        cache_misses: 0,
        downstream_calls: 0,
        api_queue: 0,
        request_durations: [],
    };
    res.json({ status: 'cache cleared' });
});

if (require.main === module) {
    app.listen(PORT, () => {
        console.log(`API server running on http://localhost:${PORT}`);
        console.log(`Cache mode: ${CACHE_MODE}, TTL: ${CACHE_TTL}ms`);
    });
}

module.exports = { app, metrics, cache };