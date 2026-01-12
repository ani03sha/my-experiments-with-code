const axios = require('axios');
const key = process.argv[2] || 'test-key-' + Date.now();
const times = parseInt(process.argv[3]) || 5;

async function sendRequest() {
    try {
        const response = await axios.post('http://localhost:3000/charge',
            { amount: 100 },
            { headers: { 'Idempotency-Key': key } }
        );
        console.log(`Response: ${JSON.stringify(response.data)}`);
    } catch (err) {
        console.log(`Error: ${err.message}`);
    }
}

(async () => {
    console.log(`Sending ${times} requests with key: ${key}`);
    for (let i = 0; i < times; i++) {
        await sendRequest();
        await new Promise(resolve => setTimeout(resolve, 100));
    }
})();