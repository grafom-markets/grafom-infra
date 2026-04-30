#!/usr/bin/env bash
# retry-oracle.sh — Retry Oracle A1 creation, starting small then scaling up
#
# Usage:
#   ./terraform/retry-oracle.sh              # retry every 60 seconds
#   ./terraform/retry-oracle.sh 120          # retry every 120 seconds
#
# Strategy: try largest allocation first, fall back to smaller sizes.
# Once provisioned at any size, resize later with:
#   tofu apply -var="oracle_ocpus=4" -var="oracle_memory_gb=24"

set -uo pipefail

INTERVAL="${1:-60}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ATTEMPT=0

# Sizes to try — largest first, fall back to smaller
SIZES=("4:24" "2:12" "1:6")

echo "=== Oracle A1 Retry Script ==="
echo "Region:   ap-mumbai-1 (home region, always-free)"
echo "Shape:    VM.Standard.A1.Flex"
echo "Strategy: try 4/24 → 2/12 → 1/6 OCPU/GB"
echo "Interval: ${INTERVAL}s between full cycles"
echo "Press Ctrl+C to stop"
echo ""

while true; do
    for SIZE in "${SIZES[@]}"; do
        OCPUS="${SIZE%%:*}"
        MEMORY="${SIZE##*:}"
        ATTEMPT=$((ATTEMPT + 1))

        echo "[$(date '+%H:%M:%S')] Attempt #${ATTEMPT} — ${OCPUS} OCPU / ${MEMORY} GB RAM"

        cd "$SCRIPT_DIR" && tofu apply -auto-approve \
            -var="cloud_provider=oracle" \
            -var="region=ap-mumbai-1" \
            -var="instance_type=VM.Standard.A1.Flex" \
            -var="environment=dev" \
            -var="oracle_ocpus=${OCPUS}" \
            -var="oracle_memory_gb=${MEMORY}" 2>&1 | tail -5

        if [ $? -eq 0 ]; then
            echo ""
            echo "=== SUCCESS! Instance created ==="
            echo "Size: ${OCPUS} OCPU / ${MEMORY} GB RAM"
            tofu output
            if [ "$OCPUS" -lt 4 ]; then
                echo ""
                echo ">>> Provisioned at reduced size. To scale up later:"
                echo "    cd terraform && tofu apply -var='oracle_ocpus=4' -var='oracle_memory_gb=24'"
            fi
            exit 0
        fi

        echo "  No capacity for ${OCPUS}/${MEMORY}. Trying smaller..."
        sleep 5
    done

    echo ""
    echo "[$(date '+%H:%M:%S')] Full cycle done. Waiting ${INTERVAL}s..."
    sleep "$INTERVAL"
done
