const { initDB } = require('./db.js');
const fs = require('fs');

const CRASH_AFTER = process.env.CRASH_AFTER ? parseInt(process.env.CRASH_AFTER) : 0;

let processedCount = 0;

async function processFromQueue() {
    const db = await initDB();
    if (fs.existsSync('queue.txt')) {
        const content = fs.readFileSync('queue.txt', 'utf8').trim();
        if (!content) return;

        const lines = content.split('\n');
        for (const line of lines) {
            if (!line) continue;
            const [chargeId, amount] = line.split(',');

            // Check if already processed (idempotent side-effect)
            const charge = await db.get('SELECT status FROM charges WHERE id = ?', [chargeId]);
            if (charge && charge.status === 'processed') {
                console.log(`Skipping already processed charge ${chargeId}`);
                continue;
            }

            await db.run('UPDATE charges SET status = ? WHERE id = ?', ['processed', chargeId]);
            fs.appendFileSync('processed.log', `Worker processed charge ${chargeId} for $${amount} at ${new Date().toISOString()}\n`);
            processedCount++;
            if (CRASH_AFTER > 0 && processedCount >= CRASH_AFTER) {
                console.log(`💥 Simulating worker crash after ${processedCount} messages`);
                process.exit(1);
            }
        }
        fs.writeFileSync('queue.txt', ''); // Clear processed messages
    }
}

setInterval(processFromQueue, 2000);
console.log('Worker started with crash simulation:', CRASH_AFTER);