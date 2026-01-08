const express = require('express');
const { createProxyMiddleware } = require('http-proxy-middleware');
const { spawn } = require('child_process');

class Dispatcher {
    constructor() {
        this.app = express();
        this.instances = [];
        this.instanceCounter = 0;
        this.metrics = {
            active_instances: 0,
            requests_total: 0,
            requests_by_instance: {},
            queue_depths: {}
        };

        this.setupMiddleware();
        this.setupRoutes();

        // Start with 1 instance
        this.addInstance();
    }

    setupMiddleware() {
        this.app.use(express.json());
        this.app.use((req, res, next) => {
            this.metrics.requests_total++;
            next();
        });
    }

    setupRoutes() {
        // Metrics endpoint - aggregate metrics from all instances
        this.app.get('/metrics', async (req, res) => {
            const http = require('http');
            const instanceMetrics = [];

            // Fetch metrics from all instances
            for (const instance of this.instances) {
                try {
                    const metrics = await new Promise((resolve, reject) => {
                        const timeout = setTimeout(() => reject(new Error('timeout')), 500);
                        const req = http.get(`http://localhost:${instance.port}/metrics`, {timeout: 500}, (resp) => {
                            let data = '';
                            resp.on('data', chunk => data += chunk);
                            resp.on('end', () => {
                                clearTimeout(timeout);
                                try {
                                    resolve(JSON.parse(data));
                                } catch (e) {
                                    reject(e);
                                }
                            });
                        }).on('error', (err) => {
                            clearTimeout(timeout);
                            reject(err);
                        });
                        req.on('timeout', () => {
                            req.destroy();
                            reject(new Error('timeout'));
                        });
                    });
                    instanceMetrics.push(metrics);
                } catch (err) {
                    // Instance not ready yet, skip
                }
            }

            // Aggregate p95 from all instances
            const allP95s = instanceMetrics.map(m => m.p95_estimate || 0).filter(p => p > 0);
            const avgP95 = allP95s.length > 0 ? allP95s.reduce((a, b) => a + b, 0) / allP95s.length : 0;

            res.json({
                dispatcher_active_instances: this.metrics.active_instances,
                dispatcher_requests_total: this.metrics.requests_total,
                dispatcher_queue_depths: this.metrics.queue_depths,
                dispatcher_requests_by_instance: this.metrics.requests_by_instance,
                p95_estimate: avgP95,
                instance_metrics: instanceMetrics,
                timestamp: Date.now()
            });
        });

        // Scale control endpoints
        this.app.post('/scale-up', (req, res) => {
            this.addInstance();
            res.json({
                success: true,
                instances: this.instances.length
            });
        });

        this.app.post('/scale-down', (req, res) => {
            if (this.instances.length > 1) {
                this.removeInstance();
                res.json({
                    success: true,
                    instances: this.instances.length
                });
            } else {
                res.status(400).json({ error: 'Cannot scale below 1 instance' });
            }
        });

        // Dynamic proxy for API instances
        this.app.all('/work', (req, res) => {
            if (this.instances.length === 0) {
                return res.status(503).json({ error: 'No instances available' });
            }

            // Round-robin selection
            const instance = this.instances[Math.floor(Math.random() * this.instances.length)];
            const instanceKey = instance.port.toString();

            // Track queue depth
            this.metrics.queue_depths[instanceKey] = (this.metrics.queue_depths[instanceKey] || 0) + 1;

            // Create proxy middleware on the fly
            const proxy = createProxyMiddleware({
                target: `http://localhost:${instance.port}`,
                changeOrigin: true,
                onProxyReq: (proxyReq, req, res) => {
                    // Headers to add request
                    proxyReq.setHeader('X-Dispatcher-Instance', instanceKey);
                },
                onProxyRes: (proxyRes, req, res) => {
                    // Decrement queue depth when request completes
                    this.metrics.queue_depths[instanceKey] = Math.max(0, (this.metrics.queue_depths[instanceKey] || 0) - 1);
                },
                onError: (err, req, res) => {
                    this.metrics.queue_depths[instanceKey] = Math.max(0, (this.metrics.queue_depths[instanceKey] || 0) - 1);

                    res.status(500).json({
                        error: 'Instance unavailable',
                        shed: true,
                        instance: instanceKey
                    });
                }
            });
            return proxy(req, res);
        });

        // Health check
        this.app.get('/health', (req, res) => {
            res.json({
                status: 'healthy',
                instances: this.instances.length,
                timestamp: Date.now()
            });
        });
    }

    addInstance() {
        const port = 3000 + this.instances.length;
        const instance = spawn('node', ['api_instance.js'], {
            env: {
                ...process.env,
                PORT: port.toString(),
                POOL_SIZE: process.env.POOL_SIZE || '4',
                SHED_THRESHOLD: process.env.SHED_THRESHOLD || '10',
                DEGRADE_MODE: process.env.DEGRADE_MODE || '0',
                INSTANCE_ID: `instance-${this.instanceCounter++}`
            },
            stdio: ['ignore', 'pipe', 'pipe']
        });

        instance.port = port;

        // Log instance output
        instance.stdout.on('data', (data) => {
            console.log(`[Instance ${port}] ${data.toString().trim()}`);
        });

        instance.stderr.on('data', (data) => {
            console.error(`[Instance ${port} ERROR] ${data.toString().trim()}`);
        });

        instance.on('exit', (code) => {
            const index = this.instances.findIndex(inst => inst.port === port);
            if (index > -1) {
                this.instances.splice(index, 1);
                delete this.metrics.queue_depths[port];
                delete this.metrics.requests_by_instance[port];
                this.metrics.active_instances = this.instances.length;
                console.log(`Instance on port ${port} removed (exit code: ${code})`);
            }
        });

        this.instances.push(instance);
        this.metrics.active_instances = this.instances.length;
        this.metrics.queue_depths[port] = 0;
        this.metrics.requests_by_instance[port] = 0;

        console.log(`Added instance on port ${port}`);
        return instance;
    }

    removeInstance() {
        if (this.instances.length === 0) {
            return;
        }

        const instance = this.instances.pop();
        console.log(`Removing instance on port ${instance.port}`);
        instance.kill('SIGTERM');
    }

    start(port = 8080) {
        this.server = this.app.listen(port, () => {
            console.log(`Dispatcher listening on port ${port}`);
            console.log(`Initial instance on port ${this.instances[0].port}`);
            console.log(`Metrics available at http://localhost:${port}/metrics`);
        });
    }

    shutdown() {
        console.log('Shutting down dispatcher and all instances...');
        this.instances.forEach(instance => instance.kill('SIGTERM'));
        if (this.server) {
            this.server.close();
        }
    }
}

// Start if run directly
if (require.main === module) {
    const dispatcher = new Dispatcher();
    dispatcher.start();

    // Handle graceful shutdown
    process.on('SIGINT', () => {
        console.log('\nReceived SIGINT, shutting down gracefully...');
        dispatcher.shutdown();
        setTimeout(() => process.exit(0), 1000);
    });

    process.on('SIGTERM', () => {
        console.log('\nReceived SIGTERM, shutting down gracefully...');
        dispatcher.shutdown();
        setTimeout(() => process.exit(0), 1000);
    });
}

module.exports = Dispatcher;