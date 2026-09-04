# scripts/chaos-scenarios.sh
#!/usr/bin/env bash
set -euo pipefail

# 1. Forced OOM via oversized token request
curl -s -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"mistralai/Mistral-7B-Instruct-v0.3","messages":[{"role":"user","content":"repeat forever"}],"max_tokens":32000}'

# 2. CUDA driver mismatch container failure
kubectl set image deployment/vllm-deployment vllm=vllm/vllm-openai:cuda12.1-mismatch-tag

# 3. Node drain during active inference (cold-start reload test)
kubectl drain $(kubectl get nodes -l nvidia.com/gpu.present=true -o jsonpath='{.items[0].metadata.name}') \
  --ignore-daemonsets --delete-emptydir-data --force

# 4. Taint/toleration verification for non-GPU pods
kubectl run non-gpu-test --image=busybox --restart=Never -- sleep 3600
kubectl get pod non-gpu-test -o wide
