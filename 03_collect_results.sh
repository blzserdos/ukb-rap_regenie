#!/usr/bin/env bash
# 03_collect_results.sh — merge per-chromosome regenie results and download
#
# Run locally after all step 2 jobs have completed.
# Downloads per-chromosome .regenie.gz files from RAP, merges them,
# and saves merged summary statistics locally.
#
# Usage:
#   bash 03_collect_results.sh [--pheno PHENO]
#
# If --pheno is not provided, defaults to PHENO_COLS from config.sh.

set -euo pipefail
source "$(dirname "$0")/config.sh"

PHENO="${PHENO_COLS}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pheno) PHENO="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

RESULTS_DIR="results"
mkdir -p "${RESULTS_DIR}"

echo "Processing phenotype: ${PHENO}"
OUT_FILE="${RESULTS_DIR}/${PHENO}_gwas.regenie.gz"

FIRST=1
for CHR in ${AUTOSOMES}; do
    REMOTE_FILE="${OUTPUT_DIR}/step2/step2_output/step2_chr${CHR}_${PHENO}.regenie.gz"

    # Check the file exists on RAP before downloading
    if ! dx describe "${REMOTE_FILE}" &>/dev/null; then
        echo "  WARNING: ${REMOTE_FILE} not found on RAP — skipping chr${CHR}"
        continue
    fi

    dx download "${REMOTE_FILE}" -o "tmp_chr${CHR}.regenie.gz" --overwrite

    if [[ "${FIRST}" -eq 1 ]]; then
        gunzip -c "tmp_chr${CHR}.regenie.gz" | gzip > "${OUT_FILE}"
        FIRST=0
    else
        gunzip -c "tmp_chr${CHR}.regenie.gz" | tail -n +2 | gzip >> "${OUT_FILE}"
    fi

    rm -f "tmp_chr${CHR}.regenie.gz"
done

NLINES=$(gunzip -c "${OUT_FILE}" | wc -l)
echo "  Merged: ${OUT_FILE} (${NLINES} lines including header)"
echo ""
echo "Results saved to: ${RESULTS_DIR}/"
ls -lh "${RESULTS_DIR}/"
