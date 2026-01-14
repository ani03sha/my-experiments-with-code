#!/bin/bash

echo "=== Sampling Demo ==="
echo

# Clean traces
> traces.ndjson

echo "1. No sampling (100%):"
node -e "
const { Tracer } = require('./instrumentation');
const tracer = new Tracer('test', 'http://localhost:9411', 1.0);
tracer.startSpan('test').finish();
" &
sleep 1
node trace_collector.js &
COLLECTOR_PID=$!
sleep 2
kill $COLLECTOR_PID
NO_SAMPLE_COUNT=$(wc -l < traces.ndjson)
echo "Spans collected: $NO_SAMPLE_COUNT"
echo

echo "2. Probabilistic sampling (10%):"
> traces.ndjson
node -e "
const { Tracer } = require('./instrumentation');
const tracer = new Tracer('test', 'http://localhost:9411', 0.1);
for(let i = 0; i < 100; i++) {
  tracer.startSpan('test').finish();
}
" &
sleep 1
node trace_collector.js &
COLLECTOR_PID=$!
sleep 2
kill $COLLECTOR_PID
PROB_SAMPLE_COUNT=$(wc -l < traces.ndjson)
echo "Spans collected: $PROB_SAMPLE_COUNT (expected ~10)"
echo

echo "3. Head-tail sampling (10% + slow ops):"
> traces.ndjson
node -e "
const { Tracer } = require('./instrumentation');
const tracer = new Tracer('test', 'http://localhost:9411', 0.1);
// Add tail threshold for head-tail
tracer.tailThreshold = 50;
for(let i = 0; i < 100; i++) {
  const latency = i === 0 ? 200 : 10; // One slow trace
  tracer.startSpan('test', null, {}, latency).finish();
}
" &
sleep 1
node trace_collector.js &
COLLECTOR_PID=$!
sleep 2
kill $COLLECTOR_PID
HEAD_TAIL_COUNT=$(wc -l < traces.ndjson)
echo "Spans collected: $HEAD_TAIL_COUNT (slow trace preserved)"
echo

echo "Sampling Summary:"
echo "- No sampling: $NO_SAMPLE_COUNT spans"
echo "- Probabilistic 10%: $PROB_SAMPLE_COUNT spans (~10% of total)"
echo "- Head-tail 10%: $HEAD_TAIL_COUNT spans (includes slow traces)"