// pace-metrics — a locked mailbox for small private metrics.
//
// It computes nothing. A publisher on a trusted machine POSTs a JSON blob;
// this Worker checks a bearer token, stores it in KV, and hands it back to
// anything presenting the *read* token. Two separate tokens on purpose: the
// recurring job that writes can only ever overwrite one key, and the thing
// that reads (a watch complication) can never write.
//
// Routes:
//   GET  /v1/<name>   Authorization: Bearer <READ_TOKEN>    -> stored JSON
//   POST /v1/<name>   Authorization: Bearer <WRITE_TOKEN>   -> {"ok":true}

const JSON_HEADERS = {
  'content-type': 'application/json; charset=utf-8',
  // Complica decides its own refresh cadence; never let an edge cache serve a
  // value older than the one KV already has.
  'cache-control': 'no-store',
};

const KEY_PATTERN = /^\/v1\/([a-z0-9][a-z0-9-]{0,31})$/;
const MAX_BODY_BYTES = 8192;

// Length-then-XOR compare. Leaks the token's length, which is fixed and public
// anyway; does not leak where two same-length tokens first differ.
function tokensMatch(given, expected) {
  if (typeof given !== 'string' || typeof expected !== 'string') return false;
  if (given.length === 0 || given.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < given.length; i++) diff |= given.charCodeAt(i) ^ expected.charCodeAt(i);
  return diff === 0;
}

function bearer(request) {
  const header = request.headers.get('authorization') || '';
  return header.startsWith('Bearer ') ? header.slice(7) : '';
}

const reply = (obj, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: JSON_HEADERS });

export default {
  async fetch(request, env) {
    const match = KEY_PATTERN.exec(new URL(request.url).pathname);
    // Unmatched paths 404 before any token is examined, so probing the Worker
    // reveals nothing about which keys exist.
    if (!match) return reply({ error: 'not found' }, 404);
    const key = match[1];
    const token = bearer(request);

    if (request.method === 'GET') {
      if (!tokensMatch(token, env.READ_TOKEN)) return reply({ error: 'unauthorized' }, 401);
      const stored = await env.METRICS.get(key);
      if (stored === null) return reply({ error: 'no data for ' + key }, 404);
      return new Response(stored, { headers: JSON_HEADERS });
    }

    if (request.method === 'POST' || request.method === 'PUT') {
      if (!tokensMatch(token, env.WRITE_TOKEN)) return reply({ error: 'unauthorized' }, 401);
      const body = await request.text();
      if (body.length > MAX_BODY_BYTES) return reply({ error: 'body too large' }, 413);
      try {
        JSON.parse(body);
      } catch {
        return reply({ error: 'body is not valid JSON' }, 400);
      }
      await env.METRICS.put(key, body);
      return reply({ ok: true, key, bytes: body.length });
    }

    return reply({ error: 'method not allowed' }, 405);
  },
};
