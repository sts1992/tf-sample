// Pure HTTP handler, separated from AWS/database startup for offline unit tests.
function send(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(body));
}
export function createHandler({ readDatabase, writerHost, readerHost, appHost, log = console.error }) {
  return async (req, res) => {
    // Runtime health is independent of Aurora; avoid replacing healthy EC2s during DB outages.
    if (req.method === 'GET' && req.url === '/healthz') return send(res, 200, { ok: true });
    if (req.method !== 'GET' || !['/api/health', '/api/reader'].includes(req.url)) {
      return send(res, 404, { error: 'Not found' });
    }
    const role = req.url === '/api/reader' ? 'reader' : 'writer';
    try {
      const database = await readDatabase(role === 'reader' ? readerHost : writerHost);
      send(res, 200, { ok: true, demo: true, app_host: appHost, endpoint_role: role, database });
    } catch (error) {
      // Never log secret values, connection options, or raw error messages.
      log(JSON.stringify({ event: 'database_unavailable', code: error.code || error.name }));
      send(res, 503, { ok: false, error: 'Database temporarily unavailable' });
    }
  };
}
