const { initDB } = require('./db.js');

async function processOutbox() {
    const db = await initDB();
    const messages = await db.all(`
        SELECT o.id, o.charge_id, c.amount
        FROM outbox o
        JOIN charges c ON o.charge_id = c.id
        WHERE o.status = ?
        ORDER BY o.id LIMIT 10
    `, ['pending']);

    for (const msg of messages) {
        console.log(`Forwarding outbox message for charge ${msg.charge_id} (amount: ${msg.amount}) to worker`);
        // In real system: send to message queue. Here we append to queue.txt
        require('fs').appendFileSync('queue.txt', `${msg.charge_id},${msg.amount}\n`);
        await db.run('UPDATE outbox SET status = ?, attempts = attempts + 1 WHERE id = ?', ['sent', msg.id]);
    }
}
setInterval(processOutbox, 3000);
console.log('Outbox processor polling every 3s');