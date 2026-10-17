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
