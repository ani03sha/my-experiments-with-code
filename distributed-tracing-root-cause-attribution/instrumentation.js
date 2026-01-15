const { randomBytes, randomUUID } = require('crypto');

class Tracer {
    constructor(serviceName, collectorUrl, samplingRate = 1.0) {
        this.serviceName = serviceName;
        this.collectorUrl = collectorUrl;
        this.samplingRate = samplingRate;
        this.tailThreshold = 100; // ms
    }

    generateId() {
        return randomBytes(8).toString('hex');
    }

    generateTraceId() {
        return randomUUID();
    }

    shouldSample(traceId, operation, latency = 0) {
        if (this.samplingRate === 1.0) {
            return true;
        }

        // Head-tail sampling: always attempt slow operation
        if (latency > this.tailThreshold) {
            return true;
        }

        // Probabilistic sampling
        const hash = traceId.split('-')[0];
        const value = parseInt(hash, 16) / 0xFFFFFFFF;
        return value < this.samplingRate;
    }

    startSpan(operation, parentContext = null, tags = {}) {
        const traceId = parentContext?.traceId || this.generateTraceId();
        const spanId = this.generateId();
        const sampled = parentContext?.sampled ?? this.shouldSample(traceId, operation);

        const span = {
            trace_id: traceId,
            span_id: spanId,
            parent_span_id: parentContext?.spanId || null,
            service: this.serviceName,
            operation,
            start_ts_iso: new Date().toISOString(),
            tags,
            sampled
        };

        return {
            ...span,
            context: {
                traceId,
                spanId,
                sampled: sampled ? '1' : '0'
            },
            finish: (additionalTags = {}) => {
                span.end_ts_iso = new Date().toISOString();
                span.duration_ms = new Date(span.end_ts_iso) - new Date(span.start_ts_iso);
                span.tags = { ...span.tags, ...additionalTags };

                // Head-tail sampling: always send slow spans even if not initially sampled
                const shouldSend = span.sampled || (span.duration_ms > this.tailThreshold);

                if (shouldSend) {
                    // Fire-and-forget: don't block request on collector POST
                    this.sendSpan(span).catch(() => {});
                }
                return span;
            }
        };
    }

    async sendSpan(span) {
        try {
            await fetch(`${this.collectorUrl}/ingest`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(span)
            });
        } catch (error) {
            console.error('Failed to send span:', error.message);
        }
    }

    propagateHeaders(context) {
        return {
            'X-Trace-Id': context.traceId,
            'X-Span-Id': context.spanId,
            'X-Sampled': context.sampled
        };
    }

    extractHeaders(headers) {
        return {
            traceId: headers['x-trace-id'],
            spanId: headers['x-span-id'],
            sampled: headers['x-sampled'] === '1'
        }
    }

    async instrumentHTTPCall(url, options, spanName, parentSpan) {
        const childSpan = this.startSpan(spanName, parentSpan?.context);
        const headers = {
            ...options?.headers,
            ...this.propagateHeaders(childSpan.context)
        };

        try {
            const response = await fetch(url, { ...options, headers });
            childSpan.finish({
                http_status: response.status,
                http_method: options?.method || 'GET',
                target_url: url
            });
            return response;
        } catch (error) {
            childSpan.finish({
                error: error.message,
                http_method: options?.method || 'GET',
                target_url: url
            });
            throw error;
        }
    }

    instrumentAsync(fn, operation, parentContext) {
        const span = this.startSpan(operation, parentContext);
        const originalCallback = fn;

        return async (...args) => {
            try {
                const result = await originalCallback(...args);
                span.finish({ success: true });
                return result;
            } catch (error) {
                span.finish({ error: error.message, success: false });
                throw error;
            }
        };
    }
}

module.exports = { Tracer };