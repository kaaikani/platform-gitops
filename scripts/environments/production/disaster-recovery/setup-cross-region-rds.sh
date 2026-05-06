#!/bin/bash
# =============================================================================
# CROSS-REGION RDS READ REPLICA FOR DISASTER RECOVERY
# =============================================================================
# Creates a cross-region read replica of the production RDS instance
# in ap-southeast-1 (Singapore) for DR failover
#
# Architecture:
#   Primary: ap-south-1 (Mumbai) - Read/Write
#   Replica: ap-southeast-1 (Singapore) - Read-only (promotable on DR)
#
# Prerequisites:
#   - AWS CLI configured
#   - Source RDS instance exists and is running
#   - Source RDS has automated backups enabled
#
# Usage:
#   chmod +x setup-cross-region-rds.sh
#   ./setup-cross-region-rds.sh
# =============================================================================

set -euo pipefail

# Configuration
PRIMARY_REGION="ap-south-1"
DR_REGION="ap-southeast-1"
SOURCE_DB_IDENTIFIER="test-5"  # Your RDS instance identifier
DR_DB_IDENTIFIER="vendure-prod-dr"
DB_INSTANCE_CLASS="db.t3.small"  # Smaller than primary for cost savings

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() { echo -e "${GREEN}[+] $1${NC}"; }
print_warn() { echo -e "${YELLOW}[!] $1${NC}"; }

echo "=============================================="
echo "  Cross-Region RDS Read Replica Setup"
echo "=============================================="
echo "Primary:  $SOURCE_DB_IDENTIFIER ($PRIMARY_REGION)"
echo "Replica:  $DR_DB_IDENTIFIER ($DR_REGION)"
echo "Instance: $DB_INSTANCE_CLASS"
echo ""

# =============================================================================
# STEP 1: Verify source RDS instance
# =============================================================================
print_step "Step 1: Verifying source RDS instance"

SOURCE_ARN=$(aws rds describe-db-instances \
    --db-instance-identifier "$SOURCE_DB_IDENTIFIER" \
    --region "$PRIMARY_REGION" \
    --query 'DBInstances[0].DBInstanceArn' \
    --output text 2>/dev/null)

if [ -z "$SOURCE_ARN" ] || [ "$SOURCE_ARN" = "None" ]; then
    echo -e "${RED}ERROR: Source RDS instance '$SOURCE_DB_IDENTIFIER' not found in $PRIMARY_REGION${NC}"
    echo "Available instances:"
    aws rds describe-db-instances --region "$PRIMARY_REGION" \
        --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]' --output table
    exit 1
fi

# Verify automated backups are enabled
BACKUP_RETENTION=$(aws rds describe-db-instances \
    --db-instance-identifier "$SOURCE_DB_IDENTIFIER" \
    --region "$PRIMARY_REGION" \
    --query 'DBInstances[0].BackupRetentionPeriod' \
    --output text)

if [ "$BACKUP_RETENTION" = "0" ]; then
    print_warn "Enabling automated backups on source (required for replication)"
    aws rds modify-db-instance \
        --db-instance-identifier "$SOURCE_DB_IDENTIFIER" \
        --backup-retention-period 7 \
        --region "$PRIMARY_REGION" \
        --apply-immediately
    echo "Waiting for backup configuration to apply..."
    aws rds wait db-instance-available \
        --db-instance-identifier "$SOURCE_DB_IDENTIFIER" \
        --region "$PRIMARY_REGION"
fi

print_step "Source RDS ARN: $SOURCE_ARN"
print_step "Backup retention: ${BACKUP_RETENTION} days"

# =============================================================================
# STEP 2: Create cross-region read replica
# =============================================================================
print_step "Step 2: Creating cross-region read replica in $DR_REGION"

# Check if replica already exists
if aws rds describe-db-instances \
    --db-instance-identifier "$DR_DB_IDENTIFIER" \
    --region "$DR_REGION" &>/dev/null; then
    print_warn "Read replica $DR_DB_IDENTIFIER already exists in $DR_REGION"
else
    aws rds create-db-instance-read-replica \
        --db-instance-identifier "$DR_DB_IDENTIFIER" \
        --source-db-instance-identifier "$SOURCE_ARN" \
        --region "$DR_REGION" \
        --db-instance-class "$DB_INSTANCE_CLASS" \
        --storage-encrypted \
        --publicly-accessible \
        --no-multi-az \
        --tags \
            Key=Environment,Value=dr \
            Key=Project,Value=vendure \
            Key=Purpose,Value=disaster-recovery \
            Key=SourceRegion,Value="$PRIMARY_REGION"

    print_step "Read replica creation initiated. This may take 15-30 minutes."
    echo ""
    echo "Monitor progress:"
    echo "  aws rds describe-db-instances --db-instance-identifier $DR_DB_IDENTIFIER --region $DR_REGION --query 'DBInstances[0].DBInstanceStatus'"
fi

# =============================================================================
# STEP 3: Create DR failover documentation
# =============================================================================
print_step "Step 3: Generating failover documentation"

cat > /tmp/rds-failover-procedure.md <<'EOF'
# RDS Cross-Region Failover Procedure

## When to Failover
- ap-south-1 region outage lasting > 30 minutes
- Primary RDS instance unrecoverable

## Failover Steps

### 1. Promote Read Replica to Primary
```bash
aws rds promote-read-replica \
    --db-instance-identifier vendure-prod-dr \
    --region ap-southeast-1 \
    --backup-retention-period 7
```

### 2. Wait for promotion
```bash
aws rds wait db-instance-available \
    --db-instance-identifier vendure-prod-dr \
    --region ap-southeast-1
```

### 3. Get new endpoint
```bash
aws rds describe-db-instances \
    --db-instance-identifier vendure-prod-dr \
    --region ap-southeast-1 \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text
```

### 4. Update Vendure configuration
```bash
# Update the secret with new DB host
kubectl create secret generic vendure-secrets \
    --namespace vendure-production \
    --from-literal=DB_HOST=<NEW_ENDPOINT> \
    --dry-run=client -o yaml | kubectl apply -f -

# Restart Vendure pods
kubectl rollout restart deployment -n vendure-production
```

### 5. Verify application
```bash
kubectl get pods -n vendure-production
kubectl logs -n vendure-production -l app=vendure --tail=50
```

## Failback Steps (after primary region recovers)
1. Create new read replica from promoted DR instance back to ap-south-1
2. Wait for replica to sync
3. Promote the ap-south-1 replica
4. Update Vendure config back to original endpoint
5. Delete the DR replica (now standalone)

## RTO/RPO
- **RPO**: < 1 minute (async replication lag)
- **RTO**: ~15-30 minutes (promote + config update + pod restart)
EOF

echo ""
echo "=============================================="
echo "  RDS Cross-Region Replica Setup Complete"
echo "=============================================="
echo ""
echo "Primary:    $SOURCE_DB_IDENTIFIER ($PRIMARY_REGION)"
echo "DR Replica: $DR_DB_IDENTIFIER ($DR_REGION)"
echo "Instance:   $DB_INSTANCE_CLASS"
echo ""
echo "=============================================="
echo "  ESTIMATED ADDITIONAL COST:"
echo "=============================================="
echo ""
echo "  db.t3.small On-Demand ($DR_REGION): ~\$25/month"
echo "  Cross-region data transfer: ~\$2-5/month"
echo "  Total DR cost: ~\$27-30/month"
echo ""
echo "=============================================="
echo "  FAILOVER COMMAND (use in emergency):"
echo "=============================================="
echo ""
echo "  aws rds promote-read-replica \\"
echo "      --db-instance-identifier $DR_DB_IDENTIFIER \\"
echo "      --region $DR_REGION"
echo ""

rm -f /tmp/rds-failover-procedure.md
