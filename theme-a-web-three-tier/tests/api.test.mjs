import test from 'node:test';
import assert from 'node:assert/strict';
import { createHandler } from '../demo/app/handler.mjs';
async function request(path, readDatabase, method = 'GET') {
  let status, body, headers;
  const logs = [];
  const handler = createHandler({readDatabase, writerHost:'writer.example', readerHost:'reader.example', appHost:'demo-host', log:x=>logs.push(x)});
  await handler({method, url:path}, {writeHead(s,h){status=s;headers=h;},end(x){body=JSON.parse(x);}});
  return {status,body,headers,logs};
}
test('health check never calls the database', async () => {
  const result = await request('/healthz', () => assert.fail('DB must not be called'));
  assert.equal(result.status,200); assert.deepEqual(result.body,{ok:true});
});
test('writer route uses the writer endpoint', async () => {
  const result = await request('/api/health', async host => {assert.equal(host,'writer.example');return {db_time:'test',read_only:0};});
  assert.equal(result.status,200); assert.equal(result.body.endpoint_role,'writer'); assert.equal(result.body.demo,true);
});
test('reader route uses the reader endpoint', async () => {
  const result = await request('/api/reader', async host => {assert.equal(host,'reader.example');return {read_only:1};});
  assert.equal(result.status,200); assert.equal(result.body.endpoint_role,'reader');
});
test('DB errors return a safe 503 without credentials or messages', async () => {
  const result = await request('/api/health', async () => {throw Object.assign(new Error('secret-password'),{code:'ER_ACCESS_DENIED_ERROR'});});
  assert.equal(result.status,503); assert.ok(!JSON.stringify(result).includes('secret-password'));
  assert.equal(result.headers['Cache-Control'],'no-store');
});
test('unsupported paths and write methods are rejected', async () => {
  for (const [path,method] of [['/unknown','GET'],['/api/health','POST'],['/api/health?sql=DROP','GET']]) {
    const result=await request(path,()=>assert.fail('DB must not be called'),method);
    assert.equal(result.status,404);
  }
});

function response() {
  return {
    writeHead(status, headers) { this.status = status; this.headers = headers; },
    end(body) { this.body = JSON.parse(body); },
  };
}

for (const rejectDatabase of [false, true]) {
  test(`DB concurrency is bounded and capacity returns after ${rejectDatabase ? 'failure' : 'success'}`, async () => {
    let finish;
    let calls = 0;
    const gate = new Promise(resolve => { finish = resolve; });
    const handler = createHandler({
      readDatabase: async () => {
        calls += 1;
        await gate;
        if (rejectDatabase) throw new Error('private-db-error');
        return { read_only: 1 };
      },
      writerHost: 'writer.example', readerHost: 'reader.example', appHost: 'demo-host', log: () => {},
    });
    const requests = Array.from({ length: 8 }, (_, i) => handler({
      method: 'GET', url: i % 2 === 0 ? '/api/health' : '/api/reader',
    }, response()));
    try {
      const busy = response();
      await handler({ method: 'GET', url: '/api/reader' }, busy);
      assert.equal(busy.status, 503);
      assert.equal(busy.headers['Retry-After'], '1');
      assert.equal(busy.headers['Cache-Control'], 'no-store');
      assert.equal(busy.body.error, 'Service temporarily busy');
      assert.equal(calls, 8, 'overload must not start or queue more DB work');

      const health = response();
      await handler({ method: 'GET', url: '/healthz' }, health);
      assert.equal(health.status, 200, 'DB saturation must not fail the EC2 health check');
      const unknown = response();
      await handler({ method: 'POST', url: '/api/health' }, unknown);
      assert.equal(unknown.status, 404);
      assert.equal(calls, 8);
    } finally {
      finish();
      await Promise.all(requests);
    }
    const next = response();
    await handler({ method: 'GET', url: '/api/health' }, next);
    assert.equal(calls, 9, 'success and failure must both release DB capacity');
    assert.equal(next.status, rejectDatabase ? 503 : 200);
    if (rejectDatabase) assert.equal(next.body.error, 'Database temporarily unavailable');
  });
}
