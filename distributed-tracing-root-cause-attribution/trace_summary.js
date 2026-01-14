const fs = require('fs');
const express = require('express');

class TraceSummary {
    constructor(filename) {
        this.filename = filename;
        this.traces = new Map();
    }

    load() {
        const lines = fs.readFileSync(this.filename, 'utf8').trim().split('\n');
        lines.forEach(line => {
            const span = JSON.parse(line);
            if (!this.traces.has(span.trace_id)) {
                this.traces.set(span.trace_id, []);
            }
            this.traces.get(span.trace_id).push(span);
        });
    }

    buildSpanTree(spans) {
        const spanMap = new Map();
        const rootSpans = [];

        spans.forEach(span => {
            span.children = [];
            spanMap.set(span.span_id, span);
        });

        spans.forEach(span => {
            if (span.parent_span_id && spanMap.has(span.parent_span_id)) {
                spanMap.get(span.parent_span_id).children.push(span);
            } else {
                rootSpans.push(span);
            }
        });

        return rootSpans;
    }

    calculateTraceDuration(spans) {
        const start = Math.min(...spans.map(s => new Date(s.start_ts_iso)));
        const end = Math.max(...spans.map(s => new Date(s.end_ts_iso)));
        return end - start;
    }

    printWaterfall(span, depth = 0) {
        const indent = '  '.repeat(depth);
        const duration = span.duration_ms || 0;
        console.log(`${indent}${span.service}.${span.operation} - ${duration}ms`);

        span.children?.forEach(child => {
            this.printWaterfall(child, depth + 1);
        });
    }

    summarizeTopSlowest(n = 5) {
        const traceEntries = Array.from(this.traces.entries());

        const withDuration = traceEntries.map(([traceId, spans]) => ({
            traceId,
            spans,
            duration: this.calculateTraceDuration(spans)
        }));

        withDuration.sort((a, b) => b.duration - a.duration);

        console.log(`Top ${n} slowest traces:\n`);

        withDuration.slice(0, n).forEach((trace, idx) => {
            console.log(`#${idx + 1} Trace: ${trace.traceId}`);
            console.log(`Total duration: ${trace.duration}ms`);
            console.log(`Span count: ${trace.spans.length}`);

            const rootSpans = this.buildSpanTree(trace.spans);
            console.log('\nWaterfall view:');
            rootSpans.forEach(span => this.printWaterfall(span));

            // Identify dominant span
            const maxSpan = trace.spans.reduce((max, span) =>
                span.duration_ms > max.duration_ms ? span : max
            );
            console.log(`\nDominant span: ${maxSpan.service}.${maxSpan.operation} (${maxSpan.duration_ms}ms)`);
            console.log('─'.repeat(80) + '\n');
        });
    }
}

// CLI or HTTP server
if (require.main === module) {
    if (process.argv[2] === '--server') {
        const app = express();
        const summary = new TraceSummary(process.argv[3] || 'traces.ndjson');
        summary.load();

        app.get('/summary/:n', (req, res) => {
            const n = parseInt(req.params.n) || 5;
            const traceEntries = Array.from(summary.traces.entries());

            const withDuration = traceEntries.map(([traceId, spans]) => ({
                traceId,
                spans,
                duration: summary.calculateTraceDuration(spans)
            }));

            withDuration.sort((a, b) => b.duration - a.duration);

            res.json({
                top_n: n,
                traces: withDuration.slice(0, n).map(trace => ({
                    trace_id: trace.traceId,
                    duration_ms: trace.duration,
                    span_count: trace.spans.length
                }))
            });
        });

        app.get('/trace/:traceId', (req, res) => {
            const traceId = req.params.traceId;
            const spans = summary.traces.get(traceId);
            if (!spans) {
                return res.status(404).json({ error: 'Trace not found' });
            }
            res.json({
                trace_id: traceId,
                duration_ms: summary.calculateTraceDuration(spans),
                spans: spans
            });
        });

        const port = process.env.PORT || 9499;
        app.listen(port, () => {
            console.log(`Trace summary API listening on http://localhost:${port}`);
        });
    } else {
        // CLI mode
        const filename = process.argv[2] || 'traces.ndjson';
        const n = parseInt(process.argv[3]) || 5;

        const summary = new TraceSummary(filename);
        summary.load();
        summary.summarizeTopSlowest(n);
    }
}

module.exports = { TraceSummary };