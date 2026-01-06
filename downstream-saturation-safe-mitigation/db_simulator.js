// db_sim.js - FIXED with non-blocking delays
const express = require('express');
const app = express();

const DB_CONC = parseInt(process.env.DB_CONC || '5');
const WORK_MS = parseInt(process.env.WORK_MS || '50');

let active = 0;
let queue = [];
let totalRequests = 0;

// Use setTimeout for non-blocking delay
function doWork(ms, callback) {
    setTimeout(callback, ms);
}

app.get('/db', (req, res) => {
    totalRequests++;
    
    if (active >= DB_CONC) {
        queue.push({ req, res });
        return;
    }
    
    active++;
    
    // Non-blocking delay
    doWork(WORK_MS, () => {
        active--;
        res.json({ 
            ok: true, 
            workTime: WORK_MS, 
            active: active, 
            queue: queue.length 
        });
        
        // Process next in queue
        if (queue.length > 0 && active < DB_CONC) {
            const next = queue.shift();
            process.nextTick(() => {
                app.handle(next.req, next.res);
            });
        }
    });
});

app.get('/metrics', (req, res) => {
    res.type('text/plain').send(`
# HELP db_active Active requests
# TYPE db_active gauge
db_active ${active}

# HELP db_queue Queued requests
# TYPE db_queue gauge
db_queue ${queue.length}

# HELP db_concurrency Concurrency limit
# TYPE db_concurrency gauge
db_concurrency ${DB_CONC}

# HELP db_total_requests Total requests
# TYPE db_total_requests counter
db_total_requests ${totalRequests}
`);
});

app.get('/health', (req, res) => {
    res.json({ 
        healthy: true, 
        active: active, 
        queue: queue.length,
        concurrency: DB_CONC 
    });
});

const PORT = 5001;
app.listen(PORT, () => {
    console.log(`DB Simulator on port ${PORT}`);
    console.log(`Concurrency: ${DB_CONC}, Work: ${WORK_MS}ms`);
});