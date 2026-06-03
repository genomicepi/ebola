#!/usr/bin/env node

import { readFile } from 'node:fs/promises';

async function loadLocalEnv(path = '.env') {
  let content;
  try {
    content = await readFile(path, 'utf-8');
  } catch {
    return;
  }

  for (const line of content.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;

    const separatorIndex = trimmed.indexOf('=');
    if (separatorIndex === -1) continue;

    const key = trimmed.slice(0, separatorIndex).trim();
    let value = trimmed.slice(separatorIndex + 1).trim();
    if (!key || process.env[key] !== undefined) continue;

    if (
      (value.startsWith('"') && value.endsWith('"'))
      || (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    process.env[key] = value;
  }
}

await loadLocalEnv();

const TOKEN_URL = process.env.PATHOPLEXUS_TOKEN_URL
  || 'https://authentication.pathoplexus.org/realms/loculus/protocol/openid-connect/token';
const CLIENT_ID = process.env.PATHOPLEXUS_CLIENT_ID || 'backend-client';
const API_BASE_URL = process.env.PATHOPLEXUS_API_BASE_URL || 'https://backend.pathoplexus.org';
const PAYLOAD_PATH = process.env.PATHOPLEXUS_SEQSET_PAYLOAD
  || './seqsets/ebola_bdbv_seqset_update.json';

const username = process.env.PATHOPLEXUS_USERNAME || process.env.USERNAME_LOCULUS;
const password = process.env.PATHOPLEXUS_PASSWORD || process.env.PASSWORD_LOCULUS;

if (!username || !password) {
  console.error('Missing Pathoplexus credentials. Set PATHOPLEXUS_USERNAME and PATHOPLEXUS_PASSWORD.');
  process.exit(1);
}

async function readPayload() {
  const payload = JSON.parse(await readFile(PAYLOAD_PATH, 'utf-8'));
  if (!payload.seqSetId || !payload.name || !Array.isArray(payload.records)) {
    throw new Error(`Invalid SeqSet payload at ${PAYLOAD_PATH}`);
  }
  return payload;
}

async function requestToken() {
  const body = new URLSearchParams({
    username,
    password,
    grant_type: 'password',
    client_id: CLIENT_ID,
  });

  const response = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body,
  });

  const text = await response.text();
  if (!response.ok) {
    throw new Error(`Pathoplexus auth failed (${response.status}): ${text}`);
  }

  const tokenResponse = JSON.parse(text);
  if (!tokenResponse.access_token) {
    throw new Error('Pathoplexus auth response did not include an access_token');
  }

  return tokenResponse.access_token;
}

async function callPathoplexus(path, token, body, options = {}) {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    method: path === '/update-seqset' ? 'PUT' : 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  const text = await response.text();
  const data = text ? JSON.parse(text) : null;
  if (!response.ok) {
    if (
      options.allowNoChange
      && response.status === 422
      && data?.detail === 'SeqSet update must contain at least one change'
    ) {
      return {
        noChange: true,
        detail: data.detail,
      };
    }

    throw new Error(`Pathoplexus ${path} failed (${response.status}): ${text}`);
  }

  return data;
}

const payload = await readPayload();
const focalCount = payload.records.filter((record) => record.isFocal).length;
const backgroundCount = payload.records.length - focalCount;

console.log(`Updating Pathoplexus SeqSet ${payload.seqSetId}`);
console.log(`Records: ${payload.records.length.toLocaleString()} (${focalCount.toLocaleString()} focal, ${backgroundCount.toLocaleString()} background)`);

const token = await requestToken();
console.log('Authenticated with Pathoplexus');

await callPathoplexus('/validate-seqset-records', token, payload.records);
console.log('Validated SeqSet records');

const result = await callPathoplexus('/update-seqset', token, payload, { allowNoChange: true });
if (result.noChange) {
  console.log(`SeqSet ${payload.seqSetId} is already up to date; no new version created.`);
} else {
  console.log(`Updated SeqSet ${result.seqSetId} to version ${result.seqSetVersion}`);
}
