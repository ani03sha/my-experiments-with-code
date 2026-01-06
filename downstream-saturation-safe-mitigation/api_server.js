// api_server.js - With better debugging
const express = require('express');
const http = require('http');
const app = express();

const POOL_SIZE = parseInt(process.env.POOL_SIZE || '2');
const DOWNSTREAM_HOST = process.env.DOWNSTREAM_HOST || 'localhost:5001';

// SIMPLE, CORRECT POOL
let available = POOL_SIZE;
let queue = [];
let active = 0;
let totalRequests = 0;
let successfulRequests = 0;
let errorRequests = 0;

function acquire() {
    return new Promise((resolve) => {
        if (active < POOL_SIZE) {
            active++;
            resolve();
        } else {
            queue.push(resolve);
        }
    });
}

function release() {
    active--;  // This should be called
    if (queue.length > 0) {
        const next = queue.shift();
        active++;
        next();
    }
}


// Call downstream with better error handling
function callDownstream() {
    return new Promise((resolve, reject) => {
        const req = http.get(`http://${DOWNSTREAM_HOST}/db`, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                if (res.statusCode === 200) {
                    try {
                        resolve(JSON.parse(data));
                    } catch (e) {
                        reject(new Error('Invalid JSON response'));
                    }
                } else {
                    reject(new Error(`HTTP ${res.statusCode}`));
                }
            });
        });
        
        req.on('error', reject);
        
        // 1 second timeout (should be plenty for 50ms work)
        req.setTimeout(1000, () => {
            req.destroy();
            reject(new Error('Timeout'));
        });
    });
}

// Main endpoint
app.get('/work', async (req, res) => {
    let acquired = false;
    
    try {
        // Wait for pool slot
        acquired = await acquire();
        
        // Call downstream
        const result = await callDownstream();
        
        successfulRequests++;
        release();
        
        res.json({
            ok: true,
            ...result,
            queueLength: queue.length,
            active: active,
            available: available
        });
        
    } catch (error) {
        errorRequests++;
        
        if (acquired) {
            release();
        }
        
        res.status(500).json({
            error: error.message,
            queueLength: queue.length,
            active: active,
            available: available
        });
    }
});

// Metrics endpoint
app.get('/metrics', (req, res) => {
    res.type('text/plain').send(`
# HELP api_active Active requests
# TYPE api_active gauge
api_active ${active}

# HELP api_available Available slots
# TYPE api_available gauge
api_available ${available}

# HELP api_queue Queued requests
# TYPE api_queue gauge
api_queue ${queue.length}

# HELP api_pool_size Configured pool size
# TYPE api_pool_size gauge
api_pool_size ${POOL_SIZE}

# HELP api_total_requests Total requests
# TYPE api_total_requests counter
api_total_requests ${totalRequests}

# HELP api_successful_requests Successful requests
# TYPE api_successful_requests counter
api_successful_requests ${successfulRequests}

# HELP api_error_requests Error requests
# TYPE api_error_requests counter
api_error_requests ${errorRequests}
`);
});

app.get('/health', (req, res) => {
    res.json({
        healthy: true,
        pool: {
            size: POOL_SIZE,
            available: available,
            active: active,
            queue: queue.length
        },
        requests: {
            total: totalRequests,
            successful: successfulRequests,
            errors: errorRequests
        }
    });
});

const PORT = 3000;
app.listen(PORT, () => {
    console.log(`API Server on port ${PORT}, Pool size: ${POOL_SIZE}`);
});