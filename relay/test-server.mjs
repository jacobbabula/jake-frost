import { createServer } from 'node:http';
import { writeFileSync } from 'node:fs';
import { MemoryStore } from './test-store.mjs';
import { handle } from './post.mjs';

const store = new MemoryStore();
const server = createServer(async (input, output) => {
  const request = new Request('http://127.0.0.1/api/post', {
    method: input.method, headers: input.headers, body: input, duplex: 'half'
  });
  const response = await handle(request, store);
  output.writeHead(response.status, Object.fromEntries(response.headers));
  output.end(await response.text());
});
server.listen(0, '127.0.0.1', () => writeFileSync(process.argv[2], String(server.address().port)));
