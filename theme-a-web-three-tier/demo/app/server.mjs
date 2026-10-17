// Original demonstration code for this Terraform example; not the AWS workshop app.
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';
import mysql from 'mysql2/promise';
import { createHandler } from './handler.mjs';

const region = process.env.AWS_REGION;
const client = new SecretsManagerClient({ region, maxAttempts: 3 });
let cachedSecret;
let cachedUntil = 0;
const ca = fs.readFileSync(process.env.DB_CA, 'utf8');

async function credentials(forceRefresh = false) {
  if (!forceRefresh && cachedSecret && Date.now() < cachedUntil) return cachedSecret;
  const value = await client.send(new GetSecretValueCommand({ SecretId: process.env.DB_SECRET_ARN }));
  const secret = JSON.parse(value.SecretString);
  if (!secret.username || !secret.password) throw new Error('Secret is missing database credentials');
  cachedSecret = secret;
  cachedUntil = Date.now() + 60_000;
  return secret;
}
async function readDatabase(host, forceRefresh = false) {
  const secret = await credentials(forceRefresh);
  let conn;
  try {
    conn = await mysql.createConnection({
      host, port: 3306, user: secret.username, password: secret.password,
      database: process.env.DB_NAME, connectTimeout: 5_000,
      ssl: { ca, rejectUnauthorized: true, verifyIdentity: true },
    });
    // Fixed SQL only. No user-supplied query or table mutation is accepted.
    const [rows] = await conn.query({
      sql: 'SELECT CURRENT_TIMESTAMP() AS db_time, DATABASE() AS db_name, @@read_only AS read_only',
      timeout: 5_000,
    });
    return rows[0];
  } catch (error) {
    if (error.code === 'ER_ACCESS_DENIED_ERROR' && !forceRefresh) return readDatabase(host, true);
    throw error;
  } finally {
    if (conn) await conn.end();
  }
}
const server = http.createServer(createHandler({
  readDatabase,
  writerHost: process.env.DB_WRITER_HOST,
  readerHost: process.env.DB_READER_HOST,
  appHost: os.hostname(),
}));
server.requestTimeout = 15_000;
server.headersTimeout = 10_000;
server.listen(Number(process.env.PORT || 3000), '0.0.0.0');
process.on('SIGTERM', () => server.close(() => process.exit(0)));
