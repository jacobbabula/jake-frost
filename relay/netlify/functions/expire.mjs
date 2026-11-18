import { getStore } from '@netlify/blobs';
import { expire } from '../../post.mjs';

export default async function() {
  await expire(getStore({ name: 'winter-post-v1', consistency: 'strong' }));
}

export const config = { schedule: '12 * * * *' };
