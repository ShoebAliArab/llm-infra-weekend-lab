# LLM Infra Weekend Lab

An ephemeral, cost-conscious practice environment for deploying a production-style LLM inference service on AWS EKS. Built to simulate the real day-to-day of an **AI Infrastructure Engineer**: GPU-backed Kubernetes, vLLM serving, full observability, and chaos testing — spun up on demand and torn down when you're done.

## What this is

This repo deploys:
- A GPU-backed EKS cluster (T4 GPUs via `g4dn.xlarge`, scaling 0→2 nodes)
- [vLLM](https://github.com/vllm-project/vllm) serving an open-source LLM (Mistral 7B / Llama 3.2 3B) with an OpenAI-compatible API
- GPU observability via NVIDIA DCGM Exporter + Prometheus + Grafana
- A manually-triggered GitHub Actions pipeline (apply/destroy) — nothing runs on a schedule, nothing costs money while idle
- Load testing (k6) and chaos scripts to simulate real production failure modes

**Why it's designed this way:** AI infra work isn't really about the model — it's about GPU scheduling, driver/CUDA compatibility, memory pressure, cold-start latency, and cost. This lab is built to let you break those things safely and see what the failure actually looks like.

## Architecture

```
GitHub Actions (OIDC, manual trigger)
        │
        ▼
   Terraform ──► VPC ──► EKS Cluster ──► GPU Node Group (g4dn.xlarge, 0-2 nodes)
                                              │
                                              ▼
                                    NVIDIA Device Plugin (GPU discovery)
                                              │
                              ┌───────────────┼────────────────┐
                              ▼               ▼                ▼
                        DCGM Exporter   vLLM Deployment   Prometheus/Grafana
                        (GPU metrics)   (Mistral/Llama)   (dashboards + scrape)
```

## Repo structure

```
.
├── .github/workflows/
│   └── deploy.yml                    # Manual apply/destroy pipeline (OIDC auth)
├── terraform/
│   ├── backend.tf                    # S3 + DynamoDB remote state
│   ├── vpc.tf                        # EKS-ready VPC, public/private subnets, NAT
│   ├── iam.tf                        # EKS/node roles + GitHub OIDC provider
│   └── eks.tf                        # EKS cluster + GPU node group (scale 0-2)
├── k8s/
│   ├── dcgm-exporter-values.yaml     # GPU metrics exporter Helm values
│   ├── prometheus-stack-values.yaml  # kube-prometheus-stack scrape config
│   └── vllm-deployment.yaml          # vLLM Deployment + Service
└── scripts/
    ├── k6-load-test.js               # Latency/throughput load test
    └── chaos-scenarios.sh            # OOM, driver mismatch, node drain, taint checks
```

## Prerequisites

| Requirement | Notes |
|---|---|
| AWS account | With billing alerts enabled — GPU costs add up fast if left running |
| GPU instance quota | Request a service quota increase for `g4dn.xlarge` (On-Demand) before you start; can take up to a day to approve |
| S3 bucket + DynamoDB table | Must exist **before** first `terraform init` — create manually (Terraform can't bootstrap its own backend) |
| Hugging Face account | Token with access to your chosen model (Llama models require accepting Meta's license on the model page first) |
| GitHub repo secrets | `AWS_ACCOUNT_ID`, `HF_TOKEN` (see below) |

### One-time setup

1. Create the state bucket and lock table (names must match `terraform/backend.tf`):
   ```bash
   aws s3 mb s3://llm-infra-weekend-tfstate
   aws dynamodb create-table \
     --table-name llm-infra-weekend-tflock \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --billing-mode PAY_PER_REQUEST
   ```
2. In `terraform/iam.tf`, replace `YOUR_GH_ORG/YOUR_REPO` in the OIDC trust policy with your actual GitHub org and repo name.
3. Add repo secrets under **Settings → Secrets and variables → Actions**:
   - `AWS_ACCOUNT_ID` — your 12-digit AWS account ID
   - `HF_TOKEN` — Hugging Face access token

No static AWS keys are needed — the pipeline authenticates via GitHub OIDC.

## Usage

**Deploy:**
Actions tab → **LLM Infra Pipeline** → Run workflow → select `apply`.

This provisions the VPC/EKS/node group, installs the NVIDIA device plugin, DCGM exporter, kube-prometheus-stack, and deploys vLLM.

**Load test:**
```bash
kubectl port-forward svc/vllm-service 8000:8000 &
VLLM_URL=http://localhost:8000/v1/chat/completions k6 run scripts/k6-load-test.js
```

**Run chaos scenarios:**
```bash
chmod +x scripts/chaos-scenarios.sh
./scripts/chaos-scenarios.sh
```
Covers: forced OOM via oversized token request, CUDA driver mismatch failure, node drain during active inference (cold-start reload), and taint/toleration verification.

**View dashboards:**
```bash
kubectl port-forward -n monitoring svc/kps-grafana 3000:80
```
Default login: `admin` / `changeme` (change this before anything but throwaway lab use).

**Tear down:**
Actions tab → **LLM Infra Pipeline** → Run workflow → select `destroy`.
Always confirm teardown after each session — GPU nodes are the expensive part of this stack.

## Cost notes

- `g4dn.xlarge` on-demand is roughly $0.50/hr; a full weekend of active experimentation typically runs $10-25 if you destroy between sessions.
- Node group scales to 0 by default — you're only billed for GPU nodes while a pod actually requests one.
- The NAT gateway and EKS control plane (~$0.10/hr) run for as long as the cluster exists, regardless of node count — destroy the whole stack when not actively using it, not just the node group.

## Known limitations / things to harden before reuse

- The GitHub OIDC role in `iam.tf` uses `AdministratorAccess` for simplicity — scope this to EKS/EC2/VPC/IAM-specific permissions before treating this as a portfolio reference architecture.
- Grafana admin password is set in plaintext in `prometheus-stack-values.yaml` — fine for an ephemeral lab, not for anything persistent.
- Single AZ / single NAT gateway — this is a cost-optimized lab setup, not a highly-available production topology.

## What this project is for

This isn't meant to run continuously — it's a repeatable practice environment for understanding GPU scheduling, inference serving, observability, and the failure modes specific to AI infrastructure (VRAM pressure, driver mismatches, cold-start latency, node-level GPU faults). Each `apply` → break something → observe → `destroy` cycle is the point.
