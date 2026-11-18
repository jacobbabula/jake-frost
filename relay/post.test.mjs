import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { handle, expire } from './post.mjs';

class MemoryStore {
  data = new Map();
  async get(key) { return this.data.get(key) ?? null; }
  async getMetadata(key) { return this.data.has(key) ? {} : null; }
  async setJSON(key, v, options) { return this.set(key, v, options); }
  async set(key, v, { onlyIfNew } = {}) {
    if (onlyIfNew && this.data.has(key)) return { modified: false };
    this.data.set(key, v); return { modified: true };
  }
  async delete(key) { this.data.delete(key); }
  async *list({ prefix }) {
    yield { blobs: Array.from(this.data.keys()).filter(k => k.startsWith(prefix)).sort().map(key => ({ key })) };
  }
}
const token = () => randomBytes(32).toString('base64url');
const uid = () => randomBytes(16).toString('hex');
const sealed = () => randomBytes(128).toString('base64');
test('one-use invites, consent, bounded files, authenticated queue, cleanup and removal', async () => {
  const store = new MemoryStore();
  const start = new Date('2026-11-18T18:00:00Z').valueOf();
  let now = start;
  async function call(data, code=200) {
    const request = new Request('https://post.invalid/api/post', { method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data) });
    const response=await handle(request,store,now);
    assert.equal(response.status,code);return response.json();
  }
  const id=uid(),proof=token(),alice={id,token:token()},bob={id,token:token()},eve={id,token:token()};
  const invite={action:'invite',...alice,proof,name:sealed()},claim={action:'accept',...bob,proof,name:sealed()};
  const giftId=uid(),body=sealed(),send={action:'send',...alice,giftId,body};
  const poll=async c => (await call({action:'poll',contacts:[c]})).contacts[0];
  await call(invite);await call(invite);
  await call(send,403);
  await call({...claim,proof:token()},404);
  assert.equal((await poll(alice)).status,'pending');
  const racers=await Promise.all([claim,{...claim,...eve}].map(async data=>{
    const request=new Request('https://post.invalid/api/post',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
    return (await handle(request,store,now)).status;
  }));
  assert.deepEqual(racers,[200,409]);
  await call(claim);
  await call({...claim,...eve},409);
  assert.equal((await poll(eve)).status,'gone');
  assert.equal((await poll(alice)).name,claim.name);
  assert.equal((await poll(bob)).name,invite.name);
  await call({...send,body:'x'.repeat(40000)},413);
  await call({...send,body:'hello'},400);
  await call(send);await call(send);
  assert.equal((await poll(alice)).messages.length,0);
  assert.deepEqual((await poll(bob)).messages,[{id:giftId,body}]);
  await call({action:'ack',...eve,giftId},403);
  await call({action:'ack',...alice,giftId});
  assert.equal((await poll(bob)).messages.length,1);
  await call({action:'ack',...bob,giftId});assert.equal((await poll(bob)).messages.length,0);
  await call({...send,giftId:uid()});
  const abandoned={...invite,id:uid()};await call(abandoned);
  now=start+16*86400000;
  await call({...claim,id:abandoned.id},410);
  assert.equal((await poll(bob)).messages.length,0);
  await expire(store,now);
  assert.equal(await store.get('inv/'+abandoned.id),null);
  assert.equal((await poll(bob)).status,'active');
  await call({action:'remove',...bob});
  assert.equal((await poll(alice)).status,'gone');await call(send,403);
});
