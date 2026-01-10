const fetch = require('node-fetch');

const DISPATCHER_URL = process.env.DISPATCHER_URL || 'http://localhost:8080';
const POLL_INTERVAL = parseInt(process.env.POLL_INTERVAL || '5000');
const SLO_P95_MS = parseInt(process.env.SLO_P95_MS || '100');
const SLO_ERROR_RATE = parseFloat(process.env.SLO_ERROR_RATE || '0.05');
const INSTANCE_ERROR_THRESHOLD = parseInt(process.env.INSTANCE_ERROR_THRESHOLD || '10');
const SCALE_UP_COUNT = parseInt(process.env.SCALE_UP_COUNT || '1');

// State
let lastActionTime = 0;
let cooldown = 30000; // 30 seconds cooldown after action

async function getMetrics(url) {
    try {
        const response = await fetch(url + '/metrics');
        const text = await response.text();
        return text;
    } catch (err) {
        console.error(`[${new Date().toISOString()}] Failed to fetch metrics from ${url}:`, err.message);
        return '';
    }
}

function parsePrometheusMetrics(text) {
    const lines = text.split('\n');
    const metrics = {};
    for (const line of lines) {
        if (line.startsWith('#') || line.trim() === '') continue;
        const parts = line.split(' ');
        if (parts.length >= 2) {
            const metricNameWithLabels = parts[0];
            const value = parseFloat(parts[parts.length - 1]);
            // Extract base metric name (before any labels)
            const metricName = metricNameWithLabels.split('{')[0];
            metrics[metricName] = (metrics[metricName] || 0) + value;
        }
    }
    return metrics;
}

async function restartInstance(instanceUrl) {
    console.log(`[${new Date().toISOString()}] Restarting instance ${instanceUrl}`);
    // For simplicity, we just kill the process and start a new one.
    // In reality, we would need to know the PID.
    // This is a placeholder.
    // Actually, we can send a SIGTERM to the process listening on that port.
    // But for demo, we'll just log.
    // We'll implement proper process management later.
}

async function scaleUp() {
    console.log(`[${new Date().toISOString()}] Scaling up by ${SCALE_UP_COUNT} instances`);
    // Start new API instances on new ports.
    // For demo, we'll just log.
}

async function enableDegradeMode() {
    console.log(`[${new Date().toISOString()}] Enabling degrade mode on all instances`);
    // Set DEGRADE_MODE=1 on all instances via environment or endpoint.
    // For demo, we'll just log.
}

async function evaluateRules() {
    const now = Date.now();
    if (now - lastActionTime < cooldown) {
        return; // cooldown period
    }

    // Fetch dispatcher metrics
    const dispatcherMetricsText = await getMetrics(DISPATCHER_URL);
    const dispatcherMetrics = parsePrometheusMetrics(dispatcherMetricsText);
    const avgLatency = dispatcherMetrics['dispatcher_avg_latency_estimate'];
    const activeInstances = dispatcherMetrics['dispatcher_active_instances'];

    // Fetch each instance metrics
    // We need to know instance URLs. For now, assume ports 8081, 8082.
    const instanceUrls = ['http://localhost:8081', 'http://localhost:8082'];
    let totalErrors = 0;
    for (const url of instanceUrls) {
        const metricsText = await getMetrics(url);
        const metrics = parsePrometheusMetrics(metricsText);
        const instanceErrors = metrics['api_errors'] || 0;
        totalErrors += instanceErrors;
        if (instanceErrors > INSTANCE_ERROR_THRESHOLD) {
            console.log(`[${new Date().toISOString()}] Instance ${url} error count ${instanceErrors} exceeds threshold, restarting`);
            await restartInstance(url);
            lastActionTime = now;
            return;
        }
    }

    // Check overall error rate
    const errorRate = totalErrors / (totalErrors + 100); // simplistic
    if (errorRate > SLO_ERROR_RATE) {
        console.log(`[${new Date().toISOString()}] Overall error rate ${errorRate} exceeds SLO, enabling degrade mode`);
        await enableDegradeMode();
        lastActionTime = now;
        return;
    }

    // Check latency SLO
    if (avgLatency > SLO_P95_MS) {
        console.log(`[${new Date().toISOString()}] Average latency ${avgLatency}ms exceeds SLO, scaling up`);
        await scaleUp();
        lastActionTime = now;
        return;
    }
}

// Start polling
setInterval(evaluateRules, POLL_INTERVAL);
console.log(`[${new Date().toISOString()}] Remediator started, polling every ${POLL_INTERVAL}ms`);