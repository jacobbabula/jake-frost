export class MemoryStore {
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
