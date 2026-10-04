// CityPulse SMTP relay for the web build. Run:  node otp_server.js
const http = require('http');
const fs = require('fs');
const path = require('path');
const nodemailer = require('nodemailer');

const env = {};
for (const line of fs.readFileSync(path.join(__dirname, '.env'), 'utf8').split('\n')) {
  const m = line.match(/^\s*([A-Z_]+)\s*=\s*"?(.*?)"?\s*$/);
  if (m) env[m[1]] = m[2];
}
const transporter = nodemailer.createTransport({
  host: 'smtp.gmail.com',
  port: 465,
  secure: true,
  auth: { user: env.GMAIL_USER, pass: (env.GMAIL_APP_PASSWORD || '').replace(/\s/g, '') },
});

http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  if (req.method === 'OPTIONS') { res.writeHead(204); return res.end(); }
  if (req.method !== 'POST' || req.url !== '/send') { res.writeHead(404); return res.end('not found'); }
  let body = '';
  req.on('data', (c) => { body += c; if (body.length > 20000) req.destroy(); });
  req.on('end', async () => {
    try {
      const { to, subject, text } = JSON.parse(body);
      await transporter.sendMail({ from: `CityPulse <${env.GMAIL_USER}>`, to, subject, text });
      console.log('sent to', to);
      res.writeHead(200); res.end('ok');
    } catch (e) {
      console.error('send failed:', e.message);
      res.writeHead(500); res.end(String(e.message));
    }
  });
}).listen(8787, '127.0.0.1', () => console.log('CityPulse mail relay on http://localhost:8787'));
