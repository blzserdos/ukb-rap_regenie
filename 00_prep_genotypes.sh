#!/usr/bin/env bash
# 00_prep_genotypes.sh — QC array genotypes for regenie step 1
#
# Submits a single Swiss Army Knife job on DNAnexus RAP.
# Downloads UKB array genotype files per chromosome, applies QC filters,
# merges chromosomes, and LD-prunes to produce a single plink fileset for step 1.
#
# Usage (from local machine with dx CLI logged in):
#   bash 00_prep_genotypes.sh
#
# Outputs auto-uploaded by SAK to ${INPUT_DIR}/:
#   ukb_array_qc.bed / .bim / .fam   — merged QCed array genotypes
#   samples_keep.txt                  — FID/IID list from phenotype file

set -euo pipefail
source "$(dirname "$0")/config.sh"

CMD=$(cat << JOBEOF
set -eo pipefail

# ---------------------------------------------------------------------------
# 1. Build sample keep-list from phenotype file
# ---------------------------------------------------------------------------
echo "[1/4] Creating sample keep-list from phenotype file..."
dx download "${PHENO_FILE}" -o pheno.tsv
awk 'NR > 1 {print \$1, \$2}' pheno.tsv > samples_keep.txt
echo "  \$(wc -l < samples_keep.txt) samples in keep-list"

# ---------------------------------------------------------------------------
# 2. Per-chromosome QC
# ---------------------------------------------------------------------------
echo "[2/4] Per-chromosome QC..."
> merge_list.txt

for CHR in \$(seq 1 22); do
    echo "  Chromosome \${CHR}..."

    dx download "${ARRAY_GENO_DIR}/ukb22418_c\${CHR}_b0_v2.bed" -o "chr\${CHR}.bed"
    dx download "${ARRAY_GENO_DIR}/ukb22418_c\${CHR}_b0_v2.bim" -o "chr\${CHR}.bim"
    dx download "${ARRAY_GENO_DIR}/ukb22418_c\${CHR}_b0_v2.fam" -o "chr\${CHR}.fam"

    plink2 \
        --bfile "chr\${CHR}" \
        --keep samples_keep.txt \
        --geno 0.1 \
        --mind 0.1 \
        --maf 0.01 \
        --mac 50 \
        --hwe 1e-15 \
        --make-bed \
        --out "chr\${CHR}_qc" \
        --threads 8

    echo "chr\${CHR}_qc.bed chr\${CHR}_qc.bim chr\${CHR}_qc.fam" >> merge_list.txt

    rm -f "chr\${CHR}.bed" "chr\${CHR}.bim" "chr\${CHR}.fam"
done

# ---------------------------------------------------------------------------
# 3. Merge all chromosomes with plink1
# ---------------------------------------------------------------------------
echo "[3/4] Merging chromosomes..."
tail -n +2 merge_list.txt > merge_list_rest.txt

plink \
    --bfile chr1_qc \
    --merge-list merge_list_rest.txt \
    --make-bed \
    --out ukb_array_merged \
    --threads 8

rm -f chr*_qc.bed chr*_qc.bim chr*_qc.fam

# ---------------------------------------------------------------------------
# 4. LD pruning
# ---------------------------------------------------------------------------
echo "[4/4] LD pruning..."
plink2 \
    --bfile ukb_array_merged \
    --indep-pairwise 1000 100 0.9 \
    --out ukb_array_prune \
    --threads 8

plink2 \
    --bfile ukb_array_merged \
    --extract ukb_array_prune.prune.in \
    --make-bed \
    --out ukb_array_qc \
    --threads 8

echo "  Final SNP count: \$(wc -l < ukb_array_qc.bim)"
echo "  Final sample count: \$(wc -l < ukb_array_qc.fam)"

# Clean up intermediates so SAK only auto-uploads the final outputs
rm -f ukb_array_merged.bed ukb_array_merged.bim ukb_array_merged.fam
rm -f ukb_array_prune.prune.in ukb_array_prune.prune.out ukb_array_prune.log
rm -f merge_list.txt merge_list_rest.txt pheno.tsv

echo "Done. SAK will auto-upload ukb_array_qc.* and samples_keep.txt to destination."
JOBEOF
)

echo "Submitting genotype prep job..."
JOB_ID=$(dx run app-swiss-army-knife \
    --instance-type "${STEP1_INSTANCE}" \
    --priority normal \
    -icmd="${CMD}" \
    --name "regenie_prep_genotypes" \
    --destination "${INPUT_DIR}" \
    -y --brief)

echo "Genotype prep job submitted: ${JOB_ID}"
echo "Monitor with: dx watch ${JOB_ID}"
echo "Wait for completion with: dx wait ${JOB_ID}"
