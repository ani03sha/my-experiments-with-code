const http = require('http');
const express = require('express');

class Autoscaler {
    constructor() {
        this.minInstances = 1;
        this.maxInstances = 5;
        this.scaleUpThreshold = 100; // ms p95
        this.scaleDownThreshold = 30; // ms p95
        this.scaleUpTime = 5000; // ms
        this.scaleDownTime = 30000; // ms
        this.highLatencyStart = null;
        this.lowLatencyStart = null;
        this.currentInstances = 1;
        this.scaleHistory = [];

        this.app = express();
        this.setupAPI();

        console.log('Autoscaler started');
        console.log(`Config: scale up if p95 > ${this.scaleUpThreshold}ms for ${this.scaleUpTime / 1000}s`);
        console.log(`Config: scale down if p95 < ${this.scaleDownThreshold}ms for ${this.scaleDownTime / 1000}s`);

        // Start monitoring
        this.monitor();
    }

    setupAPI() {
        this.app.get('/metrics', (req, res) => {
            res.json({
                autoscaler_active: true,
                min_instances: this.minInstances,
                max_instances: this.maxInstances,
                scale_up_threshold: this.scaleUpThreshold,
                scale_down_threshold: this.scaleDownThreshold,
                current_instances: this.currentInstances,
                scale_history: this.scaleHistory.slice(-10), // Last 10 scale events
                timestamp: Date.now()
            });
        });

        this.app.post('/config', (req, res) => {
            const {
                scaleUpThreshold,
                scaleDownThreshold,
                minInstances,
                maxInstances
            } = req.body;

            if (scaleUpThreshold) this.scaleUpThreshold = scaleUpThreshold;
            if (scaleDownThreshold) this.scaleDownThreshold = scaleDownThreshold;
            if (minInstances) this.minInstances = minInstances;
            if (maxInstances) this.maxInstances = maxInstances;

            res.json({
                success: true,
                message: 'Config updated',
                config: {
                    scaleUpThreshold: this.scaleUpThreshold,
                    scaleDownThreshold: this.scaleDownThreshold,
                    minInstances: this.minInstances,
                    maxInstances: this.maxInstances
                }
            });
        });

        // Start metrics server on port 8081
        this.app.listen(8081, () => {
            console.log('Autoscaler metrics available at http://localhost:8081/metrics');
        });
    }

    async monitor() {
        setInterval(async () => {
            try {
                const metrics = await this.fetchMetrics();
                const p95 = metrics.p95_estimate || 0;
                const activeInstances = metrics.dispatcher_active_instances || 1;
                this.currentInstances = activeInstances;

                const timestamp = new Date().toISOString();
                console.log(`[${timestamp}] p95: ${p95.toFixed(2)}ms, Instances: ${activeInstances}`);

                // Check scale up condition
                if (p95 > this.scaleUpThreshold) {
                    if (!this.highLatencyStart) {
                        this.highLatencyStart = Date.now();
                        console.log(`High latency detected (p95=${p95.toFixed(2)}ms). Monitoring for ${this.scaleUpTime / 1000}s...`);
                    } else if (Date.now() - this.highLatencyStart > this.scaleUpTime) {
                        if (activeInstances < this.maxInstances) {
                            await this.scaleUp();
                            this.highLatencyStart = null;
                        }
                    }
                } else {
                    this.highLatencyStart = null;
                }

                // Check scale down condition
                if (p95 < this.scaleDownThreshold) {
                    if (!this.lowLatencyStart) {
                        this.lowLatencyStart = Date.now();
                    } else if (Date.now() - this.lowLatencyStart > this.scaleDownTime) {
                        if (activeInstances > this.minInstances) {
                            await this.scaleDown();
                            this.lowLatencyStart = null;
                        }
                    }
                } else {
                    this.lowLatencyStart = null;
                }
            } catch (error) {
                console.error('Failed to fetch metrics:', error.message);
            }
        }, 2000); // Poll every 2 seconds
    }

    async fetchMetrics() {
        return new Promise((resolve, reject) => {
            const req = http.get('http://localhost:8080/metrics', {timeout: 2000}, (res) => {
                let data = '';
                res.on('data', chunk => data += chunk);
                res.on('end', () => {
                    try {
                        resolve(JSON.parse(data));
                    } catch (e) {
                        reject(e);
                    }
                });
            }).on('error', reject);

            req.on('timeout', () => {
                req.destroy();
                reject(new Error('Metrics fetch timeout'));
            });
        });
    }

    async scaleUp() {
        console.log(`\n=== SCALING UP (${this.currentInstances} -> ${this.currentInstances + 1}) ===`);

        const scaleEvent = {
            type: 'scale_up',
            from: this.currentInstances,
            to: this.currentInstances + 1,
            timestamp: Date.now(),
            reason: `p95 > ${this.scaleUpThreshold}ms for > ${this.scaleUpTime / 1000}s`
        };

        this.scaleHistory.push(scaleEvent);

        // Call dispatcher to add instance
        return new Promise((resolve, reject) => {
            const req = http.request(
                {
                    hostname: 'localhost',
                    port: 8080,
                    path: '/scale-up',
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    }
                },
                (res) => {
                    let data = '';
                    res.on('data', chunk => data += chunk);
                    res.on('end', () => {
                        console.log(`Scale up response: ${data}`);
                        resolve();
                    });
                }
            );

            req.on('error', reject);
            req.end();
        });
    }

    async scaleDown() {
        console.log(`\n=== SCALING DOWN (${this.currentInstances} -> ${this.currentInstances - 1}) ===`);

        const scaleEvent = {
            type: 'scale_down',
            from: this.currentInstances,
            to: this.currentInstances - 1,
            timestamp: Date.now(),
            reason: `p95 < ${this.scaleDownThreshold}ms for > ${this.scaleDownTime / 1000}s`
        };

        this.scaleHistory.push(scaleEvent);

        // Call dispatcher to remove instance
        return new Promise((resolve, reject) => {
            const req = http.request(
                {
                    hostname: 'localhost',
                    port: 8080,
                    path: '/scale-down',
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    }
                },
                (res) => {
                    let data = '';
                    res.on('data', chunk => data += chunk);
                    res.on('end', () => {
                        console.log(`Scale down response: ${data}`);
                        resolve();
                    });
                }
            );

            req.on('error', reject);
            req.end();
        });
    }
}

// Start autoscaler
const autoscaler = new Autoscaler();

// Keep running
process.on('SIGINT', () => {
    console.log('Autoscaler shutting down...');
    process.exit(0);
});