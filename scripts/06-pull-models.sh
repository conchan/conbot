#!/usr/bin/env bash
# =============================================================================
# 06-pull-models.sh
# Run this inside the AI LXC container to pull or update Ollama models.
# Edit the MODELS array below to customize which models you want.
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# --- Models to pull ----------------------------------------------------------
# Comment/uncomment or add models. Sizes are approximate compressed download sizes.
MODELS=(
  "qwen3:4b"          # ~2.6 GB  — fast, great for HA voice assistant (recommended start)
  "qwen3:14b"         # ~8.2 GB  — better reasoning, still runs well on 48 GB RAM
  # "llama3.1:8b"     # ~4.7 GB  — Meta's general-purpose model
  # "qwen3:30b-a3b"   # ~17 GB   — MoE model, near GPT-4 quality, efficient
  # "llama3.1:70b"    # ~40 GB   — maximum capability, slow on CPU-only
  # "mistral:7b"      # ~4.1 GB  — fast and capable, good for coding tasks
  # "nomic-embed-text"# ~274 MB  — text embeddings for RAG pipelines
)

# --- Verify Ollama container is running --------------------------------------
if ! docker inspect -f '{{.State.Running}}' ollama 2>/dev/null | grep -q "true"; then
  error "The 'ollama' container is not running. Start it with: cd ~/ai-stack && docker compose up -d"
fi

# --- Pull each model ---------------------------------------------------------
FAILED=()
for MODEL in "${MODELS[@]}"; do
  info "Pulling $MODEL ..."
  if docker exec ollama ollama pull "$MODEL"; then
    info "$MODEL ✓"
  else
    warn "$MODEL failed — will retry at end."
    FAILED+=("$MODEL")
  fi
done

# --- Summary -----------------------------------------------------------------
echo ""
info "Currently available models:"
docker exec ollama ollama list
echo ""

if [[ ${#FAILED[@]} -gt 0 ]]; then
  warn "The following models failed to pull. Retry manually:"
  for M in "${FAILED[@]}"; do
    echo "  docker exec ollama ollama pull $M"
  done
else
  info "All models pulled successfully."
fi

echo ""
echo "Test a model interactively:"
echo "  docker exec -it ollama ollama run qwen3:4b"
echo ""
echo "Remove a model to free disk space:"
echo "  docker exec ollama ollama rm <model-name>"
echo ""
