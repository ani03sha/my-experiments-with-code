const express = require('express');
const http = require('http');
const app = express();
const PORT = process.env.API_PORT || 3000;

// Configuration
const DOWNSTREAM_HOST = process.env.DOWNSTREAM_HOST || 'localhost';
const DOWNSTREAM_PORT = process.env.DOWNSTREAM_PORT || 3001;
const DOWNSTREAM_PATH = process.env.DOWNSTREAM_PATH || '/api';
const RETRIES = parseInt(process.env.RETRIES) || 0;
const TIMEOUT_MS = parseInt(process.env.TIMEOUT_MS) || 100;
const EXP_BACKOFF = process.env.EXP_BACKOFF === 'true';
const JITTER = process.env.JITTER === 'true';

// Metrics
let requestsTotal = 0;
let retriesTotal = 0;
let timeoutErrors = 0;
let downstreamErrors = 0;
let peakDownstreamQueue = 0;

// Poll downstream metrics to track peak queue
setInterval(async () => {
  const metrics = await getDownstreamMetrics();
  const currentQueue = metrics.peak_queued_requests || 0;
  if (currentQueue > peakDownstreamQueue) {
    peakDownstreamQueue = currentQueue;
  }
}, 200);

// Helper function to call downstream using http
function callDownstream() {
  return new Promise((resolve, reject) => {
    const req = http.request({
      hostname: DOWNSTREAM_HOST,
      port: DOWNSTREAM_PORT,
      path: DOWNSTREAM_PATH,
      method: 'GET',
      timeout: TIMEOUT_MS
    }, (res) => {
      let data = '';
      res.on('data', (chunk) => {
        data += chunk;
      });
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          if (res.statusCode >= 200 && res.statusCode < 300) {
            resolve(parsed);
          } else {
            downstreamErrors++;
            reject(new Error(`Downstream error: ${res.statusCode}`));
          }
        } catch (err) {
          reject(err);
        }
      });
    });

    req.on('error', (err) => {
      if (err.code === 'ECONNRESET' || err.message.includes('timeout')) {
        timeoutErrors++;
      }
      reject(err);
    });

    req.on('timeout', () => {
      req.destroy();
      timeoutErrors++;
      reject(new Error('Timeout'));
    });

    req.end();
  });
}

// Fetch downstream metrics
async function getDownstreamMetrics() {
  return new Promise((resolve) => {
    const req = http.request({
      hostname: 'localhost',
      port: DOWNSTREAM_PORT,
      path: '/metrics',
      method: 'GET',
      timeout: 1000
    }, (res) => {
      let data = '';
      res.on('data', (chunk) => {
        data += chunk;
      });
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch {
          resolve({ active_requests: 0, queued_requests: 0 });
        }
      });
    });

    req.on('error', () => {
      resolve({ active_requests: 0, queued_requests: 0 });
    });

    req.end();
  });
}

// Retry logic
async function callDownstreamWithRetry() {
  let attempt = 0;
  while (true) {
    attempt++;
    if (attempt > 1) {
      retriesTotal++;
    }

    try {
      const result = await callDownstream();
      return result;
    } catch (error) {
      // Give up after max retries
      if (attempt > RETRIES) {
        throw error;
      }
      // Exponential backoff with optional jitter
      if (EXP_BACKOFF) {
        const baseDelay = 50; // ms
        let delay = Math.min(1000, baseDelay * Math.pow(2, attempt - 1));
        // Jitter: ±50% randomness to prevent thundering herd
        if (JITTER) {
          delay = delay * (0.5 + Math.random());
        }
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
  }
}

app.get('/api', async (req, res) => {
  requestsTotal++;
  try {
    const result = await callDownstreamWithRetry();
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/metrics', async (req, res) => {
  const downstreamMetrics = await getDownstreamMetrics();
  res.json({
    requests_total: requestsTotal,
    retries_total: retriesTotal,
    timeout_errors: timeoutErrors,
    downstream_errors: downstreamErrors,
    downstream_active_requests: downstreamMetrics.active_requests || 0,
    downstream_queued_requests: downstreamMetrics.queued_requests || 0,
    peak_downstream_queue: peakDownstreamQueue,
  });
});

app.post('/reset', (req, res) => {
  requestsTotal = 0;
  retriesTotal = 0;
  timeoutErrors = 0;
  downstreamErrors = 0;
  peakDownstreamQueue = 0;
  res.json({ message: 'Metrics reset' });
});

app.listen(PORT, () => {
  console.log(`✅ API server listening on port ${PORT}`);
  console.log(`📋 Config: RETRIES=${RETRIES}, TIMEOUT_MS=${TIMEOUT_MS}`);
  console.log(`🔗 Downstream: http://${DOWNSTREAM_HOST}:${DOWNSTREAM_PORT}${DOWNSTREAM_PATH}`);
});