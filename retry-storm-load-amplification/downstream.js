const express = require('express');
const app = express();
const PORT = process.env.DOWNSTREAM_PORT || 3001;

// Configurable behaviour
const CONCURRENCY_LIMIT = parseInt(process.env.CONCURRENCY_LIMIT) || 10;
const FAST_LATENCY = parseInt(process.env.FAST_LATENCY) || 50;
const SLOW_LATENCY = parseInt(process.env.SLOW_LATENCY) || 1000;
const ERROR_RATE = parseFloat(process.env.ERROR_RATE) || 0.01;
const SLOW_RATE = parseFloat(process.env.SLOW_RATE) || 0.05;

// Metrics
let activeRequests = 0;
let queuedRequests = 0;
let peakQueuedRequests = 0;
let errorsTotal = 0;
let requestsTotal = 0;

// Simple request tracking
app.get('/api', async (req, res) => {
  requestsTotal++;
  
  // Check concurrency limit
  if (activeRequests >= CONCURRENCY_LIMIT) {
    queuedRequests++;
    // Track peak queue depth
    if (queuedRequests > peakQueuedRequests) {
      peakQueuedRequests = queuedRequests;
    }
    // Simulate queue wait that compounds with queue size
    // This creates the cascading failure effect
    const queueWaitTime = 30 + (queuedRequests * 5);
    await new Promise(resolve => setTimeout(resolve, queueWaitTime));
    queuedRequests--;
  }
  
  activeRequests++;
  
  try {
    // Simulate occasional slow responses
    const isSlow = Math.random() < SLOW_RATE;
    const latency = isSlow ? SLOW_LATENCY : FAST_LATENCY;
    await new Promise(resolve => setTimeout(resolve, latency));

    // Simulate occasional errors
    const isError = Math.random() < ERROR_RATE;
    if (isError) {
      errorsTotal++;
      res.status(500).json({ error: 'Internal Server Error' });
    } else {
      res.json({ success: true, latency: latency });
    }
  } finally {
    activeRequests--;
  }
});

app.get('/metrics', (req, res) => {
  res.json({
    active_requests: activeRequests,
    queued_requests: queuedRequests,
    peak_queued_requests: peakQueuedRequests,
    errors_total: errorsTotal,
    requests_total: requestsTotal,
  });
});

app.post('/reset', (req, res) => {
  activeRequests = 0;
  queuedRequests = 0;
  peakQueuedRequests = 0;
  errorsTotal = 0;
  requestsTotal = 0;
  res.json({ message: 'Metrics reset' });
});

app.listen(PORT, () => {
  console.log(`Downstream service listening on port ${PORT}`);
  console.log(`Config: CONCURRENCY_LIMIT=${CONCURRENCY_LIMIT}, ERROR_RATE=${ERROR_RATE}, SLOW_RATE=${SLOW_RATE}`);
});