import { createHash, timingSafeEqual } from 'node:crypto';

const day = 86400000;
const idPattern = /^[0-9a-f]{32}$/;
const secretPattern = /^[A-Za-z0-9_-]{43}$/;
const envelopePattern = /^[A-Za-z0-9+/]+={0,2}$/;
const digest = value => createHash('sha256').update(value).digest('hex');
const same = (a, b) => typeof a === 'string' && typeof b === 'string' &&
  a.length === 64 && b.length === 64 && timingSafeEqual(Buffer.from(a, 'hex'), Buffer.from(b, 'hex'));
const read = (store, key) => store.get(key, { type: 'json' });
const reply = (body, status = 200) => Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } });

class Problem extends Error {
  constructor(status, text) { super(text); this.status = status; }
}
function requireValue(test, message = 'Invalid request.', status = 400) {
  if (!test) throw new Problem(status, message);
}
function ciphertext(value, max) {
  return typeof value === 'string' && value.length >= 88 && value.length <= max && envelopePattern.test(value);
}
function credentials(contact) {
  requireValue(contact && idPattern.test(contact.id) && secretPattern.test(contact.token));
  return digest(contact.token);
}
function dayKey(time) { return new Date(time).toISOString().slice(0, 10); }

async function pairState(store, contact, now) {
  const token = credentials(contact);
  const [invite, claim] = await Promise.all([read(store, 'inv/' + contact.id), read(store, 'yes/' + contact.id)]);
  if (!invite || (!claim && now >= invite.until)) return { status: 'gone' };
  if (same(token, invite.owner))
    return claim ? { status: 'active', side: 'a', name: claim.name } : { status: 'pending', side: 'a' };
  if (claim && same(token, claim.guest)) return { status: 'active', side: 'b', name: invite.name };
  return { status: 'gone' };
}

async function keys(store, prefix, limit) {
  const result = [];
  for await (const page of store.list({ prefix, paginate: true })) {
    for (const { key } of page.blobs) {
      result.push(key);
      if (result.length === limit) return result;
    }
  }
  return result;
}

async function removePair(store, id) {
  await store.delete('inv/' + id);
  await store.delete('yes/' + id);
  for (const key of await keys(store, 'msg/' + id + '/', 100))
    await store.delete(key);
}

export async function expire(store, now = Date.now()) {
  const today = dayKey(now);
  // Markers are stored in lexical date order. If the hourly sweep times out, the
  // next run resumes at the oldest outstanding marker.
  for (const key of await keys(store, 'due/', 120)) {
    const [, date, kind, id, side, giftId] = key.split('/');
    if (date > today) break;
    if (kind === 'inv') {
      const [invite, claim] = await Promise.all([read(store, 'inv/' + id), read(store, 'yes/' + id)]);
      if (!invite || !claim) await removePair(store, id);
    } else if (kind === 'msg') {
      await store.delete('msg/' + id + '/' + side + '/' + giftId);
    }
    await store.delete(key);
  }
}

async function operation(store, data, now) {
  const id = data.id;
  if (data.action === 'poll') {
    requireValue(Array.isArray(data.contacts) && data.contacts.length > 0 && data.contacts.length <= 16);
    let budget = 6;
    const contacts = [];
    for (const contact of data.contacts) {
      const state = await pairState(store, contact, now);
      const messages = [];
      if (state.status === 'active' && budget > 0) {
        const box = 'msg/' + contact.id + '/' + state.side + '/';
        for (const key of await keys(store, box, budget)) {
          const gift = await read(store, key);
          if (gift && gift.until > now) messages.push({ id: key.slice(box.length), body: gift.body });
          else if (gift) await store.delete(key);
        }
        budget -= messages.length;
      }
      contacts.push({ id: contact.id, status: state.status, name: state.name, messages });
    }
    return { contacts };
  }
  const token = credentials(data);
  if (data.action === 'invite') {
    requireValue(secretPattern.test(data.proof) && ciphertext(data.name, 320));
    const record = { owner: token, proof: digest(data.proof), name: data.name, until: now + 7 * day };
    const key = 'inv/' + id;
    await store.set('due/' + dayKey(record.until + day) + '/' + key, '', { onlyIfNew: true });
    const result = await store.setJSON(key, record, { onlyIfNew: true });
    if (!result.modified) requireValue(same((await read(store, key))?.owner, token), 'Invitation unavailable.', 409);
    return {};
  }
  if (data.action === 'accept') {
    requireValue(secretPattern.test(data.proof) && ciphertext(data.name, 320));
    const invite = await read(store, 'inv/' + id);
    requireValue(invite && same(invite.proof, digest(data.proof)), 'This invitation is unavailable.', 404);
    requireValue(!same(invite.owner, token), 'This is your invitation.');
    const key = 'yes/' + id;
    const existing = await read(store, key);
    if (existing) requireValue(same(existing.guest, token), 'This invitation has already been accepted.', 409);
    else {
      requireValue(now < invite.until, 'This invitation has expired.', 410);
      const result = await store.setJSON(key, { guest: token, name: data.name }, { onlyIfNew: true });
      if (!result.modified) requireValue(same((await read(store, key))?.guest, token), 'This invitation has already been accepted.', 409);
    }
    return { name: invite.name };
  }

  const state = await pairState(store, data, now);
  if (data.action === 'remove') {
    if (state.status !== 'gone') await removePair(store, id);
    return {};
  }
  requireValue(state.status === 'active', 'This friend connection is unavailable.', 403);
  requireValue(idPattern.test(data.giftId));
  if (data.action === 'ack') {
    await store.delete('msg/' + id + '/' + state.side + '/' + data.giftId);
    return {};
  }
  requireValue(data.action === 'send' && ciphertext(data.body, 28000));
  const other = state.side === 'a' ? 'b' : 'a';
  const box = 'msg/' + id + '/' + other + '/';
  const key = box + data.giftId;
  if (await store.getMetadata(key)) return {};
  requireValue((await keys(store, box, 24)).length < 24, 'Their mailbox is full. Try after they open Jake Frost.', 409);
  const until = now + 14 * day;
  await store.set('due/' + dayKey(until + day) + '/' + key, '', { onlyIfNew: true });
  await store.setJSON(key, { body: data.body, until }, { onlyIfNew: true });
  return {};
}

export async function handle(request, store, now = Date.now()) {
  try {
    requireValue(request.method === 'POST', 'Use POST.', 405);
    requireValue(request.headers.get('Content-Type')?.split(';')[0] === 'application/json', 'Expected JSON.', 415);
    requireValue(Number(request.headers.get('Content-Length') || 0) <= 32000, 'Request is too large.', 413);
    const chunks = [];
    let size = 0;
    for await (const chunk of request.body || []) {
      size += chunk.length;
      requireValue(size <= 32000, 'Request is too large.', 413);
      chunks.push(chunk);
    }
    let data;
    try { data = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
    catch { throw new Problem(400, 'Expected JSON.'); }
    requireValue(data && typeof data === 'object');
    return reply(await operation(store, data, now));
  } catch (error) {
    return error instanceof Problem ? reply({ error: error.message }, error.status) : reply({ error: 'Delivery service unavailable. Try again.' }, 503);
  }
}
