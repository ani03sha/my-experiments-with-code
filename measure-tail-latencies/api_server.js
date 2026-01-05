const express = require('express');

const app = express();

const POOL_SIZE = parseInt(process.env.POOL_SIZE || '2');

let slots = POOL_SIZE;
let queueLength = 0;

app.get('/work', async (req, res) => {
    queueLength++;

    // Real blocking wait for pool slot
    await new Promise(resolve => {
        const check = () => {
            if (slots > 0) {
                slots--;
                queueLength--;
                resolve();
            } else {
                setTimeout(check, 1);
            }
        };
        check();
    });

    try {
        // Call DB
        const start = Date.now();
        const dbResponse = await fetch('http://localhost:5001/db');
        const dbTime = Date.now() - start;

        slots++;
        res.json({
            ok: true,
            dbTime,
            queueTime: 0
        })
    } catch (e) {
        slots++;
        res.status(503).json({
            error: e.message
        })
    }
});

app.get('/metrics', (req, res) => {
    res.send(`api_slots ${slots}\napi_queue ${queueLength}\n`);
})

app.listen(3000);