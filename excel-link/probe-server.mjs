// SURE Walk - can the Excel panel talk to a server on this laptop? (probe server)
// Run by PROBE-EXCEL-LINK.cmd. Listens on 127.0.0.1:8788 only, answers the test snippet, and logs every request it
// sees (method, path, the page's origin, and the browser's local-network headers) to excel-link-log.txt.
// It stores and sends nothing else. Stop it by closing its window.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const LOG = process.argv[2] || path.join(HERE, '..', 'excel-link-log.txt');
const PORT = 8788;
const log = s => { const l = new Date().toLocaleTimeString('en-US', { hour12: false }) + ' ' + s; console.log(l); fs.appendFileSync(LOG, l + '\r\n'); };
fs.writeFileSync(LOG, 'SURE Walk - Excel panel to laptop link probe\r\nStarted ' + new Date().toString() + '\r\n\r\n');

const RELAY = `<!doctype html><meta charset="utf-8"><title>SURE Walk link test</title>
<body style="font:15px Segoe UI,system-ui,sans-serif;padding:24px">
<h3>SURE Walk link test window</h3><p id="s">Waiting for the Excel panel… (you can leave this open)</p>
<script>
addEventListener('message', async e => {
  if (e.data && e.data.sw === 'result') { try { await fetch('/result', { method: 'POST', body: e.data.text }); } catch (x) {} return; }
  if (!e.data || e.data.sw !== 'probe') return;
  let r; try { r = await (await fetch('/ping?via=relay&from=' + encodeURIComponent(e.origin))).text(); } catch (x) { r = 'relay fetch failed: ' + x.message; }
  e.source.postMessage({ sw: 'probe-reply', id: e.data.id, text: r }, e.origin);
  document.getElementById('s').textContent = 'Answered the Excel panel (' + e.origin + '). You can close this window.';
});
if (window.opener) { try { window.opener.postMessage({ sw: 'relay-ready' }, '*'); } catch (x) {} }
</script>`;

http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x');
  const h = req.headers;
  const bits = [req.method, u.pathname + (u.search || ''), 'origin=' + (h.origin || '-')];
  if (h['access-control-request-private-network']) bits.push('asks-private-network=' + h['access-control-request-private-network']);
  if (h['access-control-request-local-network']) bits.push('asks-local-network=' + h['access-control-request-local-network']);
  if (h['access-control-request-headers']) bits.push('asks-headers=' + h['access-control-request-headers']);
  if (h['sec-fetch-site']) bits.push('fetch-site=' + h['sec-fetch-site']);
  if (h['sec-fetch-dest']) bits.push('fetch-dest=' + h['sec-fetch-dest']);
  log('request ' + bits.join(' '));
  const cors = {
    'Access-Control-Allow-Origin': h.origin || '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-Access-Token',
    'Access-Control-Allow-Private-Network': 'true',
    'Access-Control-Allow-Local-Network': 'true',
    'Access-Control-Max-Age': '60',
    'Vary': 'Origin',
  };
  if (req.method === 'OPTIONS') { res.writeHead(204, cors); return res.end(); }
  if (u.pathname === '/ping') { res.writeHead(200, Object.assign({ 'Content-Type': 'text/plain' }, cors)); return res.end('pong'); }
  if (u.pathname === '/relay') { res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); return res.end(RELAY); }
  if (u.pathname === '/result' && req.method === 'POST') {
    let b = ''; req.on('data', d => { b += d; if (b.length > 20000) req.destroy(); });
    req.on('end', () => { log('RESULTS from the panel:\r\n' + b.slice(0, 20000)); res.writeHead(200, cors); res.end('ok'); });
    return;
  }
  res.writeHead(404, cors); res.end('not found');
}).listen(PORT, '127.0.0.1', () => {
  log(`listening on http://127.0.0.1:${PORT} - now open the "SURE Walk link test" snippet in Excel and click Run all tests`);
});
