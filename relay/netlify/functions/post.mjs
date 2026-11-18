import { getStore, getDeployStore } from '@netlify/blobs';
import { handle } from '../../post.mjs';

export default function(request, context) {
  const store = context.deploy.context === 'production'
    ? getStore({ name: 'winter-post-v1', consistency: 'strong' })
    : getDeployStore({ name: 'winter-post-v1', consistency: 'strong' });
  return handle(request, store);
}

export const config = {
  path: '/api/post',
  method: 'POST',
  rateLimit: { windowSize: 60, windowLimit: 60, aggregateBy: ['ip', 'domain'] }
};
