const express = require('express');
const axios = require('axios');

const app = express();
app.use(express.json({ limit: '10mb' }));

const DISCORD_WEBHOOK_URL = process.env.DISCORD_WEBHOOK_URL;
if (!DISCORD_WEBHOOK_URL) {
  console.error('DISCORD_WEBHOOK_URL is not set');
  process.exit(1);
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

// Send one chunk to Discord, respecting Discord's rate limit (429 + retry_after)
async function sendToDiscord(chunk, attempt = 1) {
  try {
    await axios.post(DISCORD_WEBHOOK_URL, { content: chunk }, {
      headers: { 'Content-Type': 'application/json' },
      timeout: 5000
    });
  } catch (error) {
    const status = error.response?.status;

    if (status === 429 && attempt <= 3) {
      const retryAfterMs = Math.min((error.response.data?.retry_after || 1) * 1000, 10_000);
      console.warn(`Discord rate limited (attempt ${attempt}), retrying in ${retryAfterMs}ms`);
      await sleep(retryAfterMs);
      return sendToDiscord(chunk, attempt + 1);
    }

    console.error('Failed to send chunk to Discord:', error.response?.data || error.message);
    throw error;
  }
}

app.post('/alertmanager', async (req, res) => {
  const alerts = req.body.alerts;

  if (!Array.isArray(alerts) || !alerts.length) {
    console.warn('Received alert with empty or invalid alerts array');
    return res.status(400).send('No alerts to process');
  }

  const messages = alerts.map(alert => {
    const summary = alert.annotations?.summary || alert.labels?.alertname || 'No summary';
    const status = alert.status || 'unknown';
    const description = alert.annotations?.description || '';
    return `**Alert:** ${summary}\nStatus: ${status}\n${description}`;
  });

  // Chunk messages to stay under Discord's 2000 char limit per message
  const chunks = [];
  let current = '';
  for (const msg of messages) {
    if ((current + '\n\n' + msg).length > 1900) {
      chunks.push(current);
      current = msg;
    } else {
      current = current ? current + '\n\n' + msg : msg;
    }
  }
  if (current) chunks.push(current);

  // Respond to Alertmanager immediately — don't make it wait on Discord's rate limit.
  // Alertmanager's own retry-on-failure logic isn't useful here anyway (it gives up
  // after 1 attempt), so we ack receipt and handle delivery async.
  res.status(200).send(`Accepted ${alerts.length} alert(s), forwarding ${chunks.length} chunk(s)`);

  let sent = 0;
  let failed = 0;
  for (const chunk of chunks) {
    try {
      await sendToDiscord(chunk);
      sent++;
    } catch (error) {
      failed++;
    }
    await sleep(1200); // stay safely under Discord's ~5 requests/2s webhook limit
  }

  console.log(`Discord forwarding complete: ${sent} sent, ${failed} failed, ${chunks.length} total`);
});

app.get('/alertmanager', (req, res) => {
  res.send('Alertmanager webhook server is running');
});

app.get('/healthz', (req, res) => {
  res.status(200).send('ok');
});

const PORT = process.env.PORT || 3002;
app.listen(PORT, () => {
  console.log(`Alertmanager webhook server listening on port ${PORT}`);
});
