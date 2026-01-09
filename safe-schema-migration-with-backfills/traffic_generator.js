const axios = require('axios');
const { error } = require('console');
const crypto = require('crypto');
const { version } = require('os');

const V1_BASE = 'http://localhost:3000/v1';
const V2_BASE = 'http://localhost:3001/v2';

function randomEmail() {
    return `user${crypto.randomBytes(4).toString('hex')}@example.com`;
}

function randomName() {
    const firsts = ['Alex', 'Jordan', 'Taylor', 'Morgan', 'Casey', 'Riley'];
    const lasts = ['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia'];
    return {
        first: firsts[Math.floor(Math.random() * firsts.length)],
        last: lasts[Math.floor(Math.random() * lasts.length)]
    };
}

async function v1Write() {
    try {
        const name = randomName();
        const email = randomEmail();
        const response = await axios.post(`${V1_BASE}/user`, {
            email,
            first_name: name.first,
            last_name: name.last,
        });
        return { success: true, id: response.data.id, version: 'v1' };
    } catch (err) {
        return { success: false, error: err.message, version: 'v1' };
    }
}

async function v2Write() {
    try {
        const name = randomName();
        const email = randomEmail();
        const response = await axios.post(`${V2_BASE}/user`, {
            email,
            full_name: `${name.first} ${name.last}`
        });

        return { success: true, id: response.data.id, version: 'v2' }
    } catch (err) {
        return { success: false, error: err.message, version: 'v2' };
    }
}

async function readRandomUser(v2Ratio = 0.0) {
    try {
        // Pick random id between 1-100
        const id = Math.floor(Math.random() * 100) + 1;
        const version = Math.random() < v2Ratio ? 'v2' : 'v1';
        const base = version === 'v1' ? V1_BASE : V2_BASE;

        const response = await axios.get(`${base}/user/${id}`);
        return { success: true, version, data: response.data };
    } catch (err) {
        return { success: false, error: err.message };
    }
}

async function runTraffic(durationMs = 60000, v2Ratio = 0.0) {
    console.log(`Running traffic for ${durationMs / 1000}s, V2 ratio: ${v2Ratio}`);

    const endTime = Date.now() + durationMs;
    const stats = {
        v1_writes: { success: 0, error: 0 },
        v2_writes: { success: 0, error: 0 },
        reads: { success: 0, error: 0 }
    }

    while (Date.now() < endTime) {
        // Random operation
        const op = Math.random();

        if (op < 0.4) { // 40% writes
            if (Math.random() < v2Ratio) {
                const result = await v2Write();
                if (result.success) {
                    stats.v2_writes.success++;
                }
                else {
                    stats.v2_writes.error++;
                }
            } else {
                const result = await v1Write();
                if (result.success) {
                    stats.v1_writes.success++;
                }
                else {
                    stats.v1_writes.error++;
                }
            }
        } else { // 60% reads
            const result = await readRandomUser(v2Ratio);
            if (result.success) {
                stats.reads.success++;
            }
            else {
                stats.reads.error++;
            }
        }
        // Random delay between 50-500ms
        await new Promise(resolve =>
            setTimeout(resolve, 50 + Math.random() * 450));
    }

    console.log('\n=== Traffic Results ===');
    console.log(`V1 writes: ${stats.v1_writes.success} OK, ${stats.v1_writes.error} errors`);
    console.log(`V2 writes: ${stats.v2_writes.success} OK, ${stats.v2_writes.error} errors`);
    console.log(`Reads: ${stats.reads.success} OK, ${stats.reads.error} errors`);
}

const duration = process.argv[2] ? parseInt(process.argv[2]) * 1000 : 60000;
const v2Ratio = process.argv[3] ? parseFloat(process.argv[3]) : 0.0;

runTraffic(duration, v2Ratio).catch(console.error);