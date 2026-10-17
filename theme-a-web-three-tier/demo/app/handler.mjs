// Pure HTTP handler, separated from AWS/database startup for offline unit tests.
function send(res, status, body, headers = {}) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...headers });
  res.end(JSON.stringify(body));
}
export function createHandler({ readDatabase, writerHost, readerHost, appHost, log = console.error }) {
  // Bound DB work per process; do not build an unbounded queue under a request burst.
  let activeDatabaseChecks = 0;
  const maxDatabaseChecks = 8;
  return async (req, res) => {
    // Runtime health is independent of Aurora; avoid replacing healthy EC2s during DB outages.
    if (req.method === 'GET' && req.url === '/healthz') return send(res, 200, { ok: true });
    if (req.method !== 'GET' || !['/api/health', '/api/reader'].includes(req.url)) {
      return send(res, 404, { error: 'Not found' });
    }
    if (activeDatabaseChecks >= maxDatabaseChecks) {
      return send(res, 503, { ok: false, error: 'Service temporarily busy' }, { 'Retry-After': '1' });
    }
    activeDatabaseChecks += 1;
    const role = req.url === '/api/reader' ? 'reader' : 'writer';
    try {
      const database = await readDatabase(role === 'reader' ? readerHost : writerHost);
      send(res, 200, { ok: true, demo: true, app_host: appHost, endpoint_role: role, database });
    } catch (error) {
      // Never log secret values, connection options, or raw error messages.
      log(JSON.stringify({ event: 'database_unavailable', code: error.code || error.name }));
      send(res, 503, { ok: false, error: 'Database temporarily unavailable' });
    } finally {
      activeDatabaseChecks -= 1;
    }
  };
}
