const express = require('express');
const fs = require('fs');
const path = require('path');

class TraceCollector {
    constructor(port = 9411) {
        this.port = port;
        this.tracesFile = path.join(__dirname, 'traces.ndjson');
        this.spansByTrace = new Map();
        this.app = express();
        this.setupMiddleware();
        this.setupRoutes();
    }

    setupMiddleware() {
        this.app.use(express.json());
    }

    setupRoutes() {
        this.app.post('/ingest', this.handleIngest.bind(this));
        this.app.get('/trace/:traceId', this.handleGetTrace.bind(this));
    }

    async handleIngest(req, res) {
        const span = req.body;

        // Respect X-Sampled header if present
        if (span.sampled === false) {
            res.status(200).end();
            return;
        }

        // Append to NDJSON file
        fs.appendFileSync(this.tracesFile, JSON.stringify(span) + '\n');

        // Store in memory for quick retrieval
        if (!this.spansByTrace.has(span.trace_id)) {
            this.spansByTrace.set(span.trace_id, []);
        }
        this.spansByTrace.get(span.trace_id).push(span);

        res.status(200).end();
    }

    async handleGetTrace(req, res) {
        const traceId = req.params.traceId;
        const spans = this.spansByTrace.get(traceId) || [];
        res.json(spans);
    }

    start() {
        this.server = this.app.listen(this.port, () => {
            console.log(`Trace collector listening on http://localhost:${this.port}`);
        });
    }

    stop() {
        if (this.server) {
            this.server.close();
        }
    }
}

// Start collector
if (require.main === module) {
    const collector = new TraceCollector();
    collector.start();
}

module.exports = { TraceCollector };