// scripts/k6-load-test.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 10,
  duration: '60s',
};

const URL = __ENV.VLLM_URL || 'http://localhost:8000/v1/chat/completions';

export default function () {
  const payload = JSON.stringify({
    model: 'mistralai/Mistral-7B-Instruct-v0.3',
    messages: [{ role: 'user', content: 'Explain Kubernetes taints in one paragraph.' }],
    max_tokens: 200,
  });

  const params = { headers: { 'Content-Type': 'application/json' } };
  const res = http.post(URL, payload, params);

  check(res, {
    'status is 200': (r) => r.status === 200,
    'has completion': (r) => r.json('choices.0.message.content') !== undefined,
  });

  sleep(1);
}
