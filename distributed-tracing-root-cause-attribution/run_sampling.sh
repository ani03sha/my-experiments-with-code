#!/bin/bash

echo "=== Sampling Demo ==="
echo

# Clean traces
> traces.ndjson

echo "1. No sampling (100%):"
# Start collector FIRST
node trace_collector.js &
COLLECTOR_PID=$!
sleep 1

# Send 10 spans with 100% sampling
node -e "
const { Tracer } = require('./instrumentation');
const tracer = new Tracer('test', 'http://localhost:9411', 1.0);
for(let i = 0; i < 10; i++) {
  tracer.startSpan('test_operation').finish();
}
"
sleep 1
kill $COLLECTOR_PID 2>/dev/null
wait $COLLECTOR_PID 2>/dev/null
NO_SAMPLE_COUNT=$(wc -l < traces.ndjson | tr -d ' ')
echo "Spans collected: $NO_SAMPLE_COUNT (expected: 10)"
echo

echo "2. Probabilistic sampling (10%):"
> traces.ndjson
# Start collector FIRST
node trace_collector.js &
COLLECTOR_PID=$!
sleep 1

# Send 100 spans with 10% sampling
node -e "
const { Tracer } = require('./instrumentation');
const tracer = new Tracer('test', 'http://localhost:9411', 0.1);
for(let i = 0; i < 100; i++) {
  tracer.startSpan('test_operation').finish();
}
"
sleep 1
kill $COLLECTOR_PID 2>/dev/null
wait $COLLECTOR_PID 2>/dev/null
PROB_SAMPLE_COUNT=$(wc -l < traces.ndjson | tr -d ' ')
echo "Spans collected: $PROB_SAMPLE_COUNT (expected: ~10)"
echo

echo "3. Head-tail sampling (10% base + slow spans always captured):"
> traces.ndjson
# Start collector FIRST
node trace_collector.js &
COLLECTOR_PID=$!
sleep 1

# Send 20 spans: 10% sampling BUT slow spans (>100ms) always captured
# We'll have 2 slow spans that should always be captured
node -e "
async function run() {
  const { Tracer } = require('./instrumentation');
  const tracer = new Tracer('test', 'http://localhost:9411', 0.1);
  tracer.tailThreshold = 100; // 100ms threshold

  for(let i = 0; i < 20; i++) {
    const span = tracer.startSpan('test_operation');

    // 2 spans will be slow (>100ms), rest are fast
    if (i === 5 || i === 15) {
      await new Promise(r => setTimeout(r, 150)); // Slow: 150ms
    } else {
      await new Promise(r => setTimeout(r, 10)); // Fast: 10ms
    }

    span.finish();
  }
}
run();
"
sleep 2
kill $COLLECTOR_PID 2>/dev/null
wait $COLLECTOR_PID 2>/dev/null
HEAD_TAIL_COUNT=$(wc -l < traces.ndjson | tr -d ' ')
echo "Spans collected: $HEAD_TAIL_COUNT"
echo "  - Expected: ~2 from 10% sampling + 2 slow spans = ~4 spans"
echo "  - The 2 slow spans (150ms > 100ms threshold) are ALWAYS captured"
echo

echo "========================================"
echo "Sampling Summary:"
echo "========================================"
echo "- No sampling (100%):    $NO_SAMPLE_COUNT spans (all captured)"
echo "- Probabilistic (10%):   $PROB_SAMPLE_COUNT spans (~10% random)"
echo "- Head-tail (10%+slow):  $HEAD_TAIL_COUNT spans (10% + guaranteed slow)"
echo
echo "Key insight: Head-tail sampling preserves debugging signal for slow"
echo "requests while reducing overall trace volume."
