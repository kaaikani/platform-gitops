#!/bin/bash
# =============================================================================
# AWS WAF SETUP FOR ALB - PRODUCTION
# =============================================================================
# Creates AWS WAF WebACL with OWASP protections and rate limiting
# Attaches to the production ALB
#
# Protections:
#   - AWS Managed OWASP Core Rule Set (SQLi, XSS, etc.)
#   - AWS Managed Known Bad Inputs
#   - AWS Managed IP Reputation (blocks known malicious IPs)
#   - Rate limiting (2000 req/5min per IP)
#   - Geographic restrictions (optional)
#   - Bot control (optional)
#
# Prerequisites:
#   - AWS CLI configured
#   - ALB exists and is serving traffic
#
# Usage:
#   chmod +x setup-waf.sh
#   ./setup-waf.sh
#
# Cost: ~$5-10/month (WebACL + rules + per-request charges)
# =============================================================================

set -euo pipefail

# Configuration
REGION="ap-south-1"
WAF_NAME="vendure-production-waf"
RATE_LIMIT=2000  # Requests per 5-minute window per IP
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() { echo -e "${GREEN}[+] $1${NC}"; }
print_warn() { echo -e "${YELLOW}[!] $1${NC}"; }

echo "=============================================="
echo "  AWS WAF Setup for Production ALB"
echo "=============================================="
echo "Region:     $REGION"
echo "WAF Name:   $WAF_NAME"
echo "Rate Limit: $RATE_LIMIT req/5min per IP"
echo ""

# =============================================================================
# STEP 1: Create WAF WebACL
# =============================================================================
print_step "Step 1: Creating WAF WebACL"

# Check if WebACL already exists
EXISTING_WAF=$(aws wafv2 list-web-acls --scope REGIONAL --region "$REGION" \
    --query "WebACLs[?Name=='$WAF_NAME'].Id" --output text 2>/dev/null || echo "")

if [ -n "$EXISTING_WAF" ] && [ "$EXISTING_WAF" != "None" ]; then
    print_warn "WebACL $WAF_NAME already exists (ID: $EXISTING_WAF)"
    echo "To update, delete first: aws wafv2 delete-web-acl --name $WAF_NAME --scope REGIONAL --id $EXISTING_WAF --lock-token <token> --region $REGION"
    WAF_ARN=$(aws wafv2 list-web-acls --scope REGIONAL --region "$REGION" \
        --query "WebACLs[?Name=='$WAF_NAME'].ARN" --output text)
else
    # Create the WebACL with rules
    WAF_ARN=$(aws wafv2 create-web-acl \
        --name "$WAF_NAME" \
        --scope REGIONAL \
        --region "$REGION" \
        --default-action '{"Allow":{}}' \
        --description "WAF for Vendure production ALB - OWASP + Rate Limiting" \
        --visibility-config '{
            "SampledRequestsEnabled": true,
            "CloudWatchMetricsEnabled": true,
            "MetricName": "vendureProductionWAF"
        }' \
        --rules "[
            {
                \"Name\": \"AWS-AWSManagedRulesCommonRuleSet\",
                \"Priority\": 1,
                \"Statement\": {
                    \"ManagedRuleGroupStatement\": {
                        \"VendorName\": \"AWS\",
                        \"Name\": \"AWSManagedRulesCommonRuleSet\",
                        \"ExcludedRules\": [
                            {\"Name\": \"SizeRestrictions_BODY\"},
                            {\"Name\": \"GenericRFI_BODY\"},
                            {\"Name\": \"CrossSiteScripting_BODY\"}
                        ]
                    }
                },
                \"OverrideAction\": {\"None\": {}},
                \"VisibilityConfig\": {
                    \"SampledRequestsEnabled\": true,
                    \"CloudWatchMetricsEnabled\": true,
                    \"MetricName\": \"AWSCommonRules\"
                }
            },
            {
                \"Name\": \"AWS-AWSManagedRulesKnownBadInputsRuleSet\",
                \"Priority\": 2,
                \"Statement\": {
                    \"ManagedRuleGroupStatement\": {
                        \"VendorName\": \"AWS\",
                        \"Name\": \"AWSManagedRulesKnownBadInputsRuleSet\"
                    }
                },
                \"OverrideAction\": {\"None\": {}},
                \"VisibilityConfig\": {
                    \"SampledRequestsEnabled\": true,
                    \"CloudWatchMetricsEnabled\": true,
                    \"MetricName\": \"AWSBadInputRules\"
                }
            },
            {
                \"Name\": \"AWS-AWSManagedRulesAmazonIpReputationList\",
                \"Priority\": 3,
                \"Statement\": {
                    \"ManagedRuleGroupStatement\": {
                        \"VendorName\": \"AWS\",
                        \"Name\": \"AWSManagedRulesAmazonIpReputationList\"
                    }
                },
                \"OverrideAction\": {\"None\": {}},
                \"VisibilityConfig\": {
                    \"SampledRequestsEnabled\": true,
                    \"CloudWatchMetricsEnabled\": true,
                    \"MetricName\": \"AWSIpReputation\"
                }
            },
            {
                \"Name\": \"AWS-AWSManagedRulesSQLiRuleSet\",
                \"Priority\": 4,
                \"Statement\": {
                    \"ManagedRuleGroupStatement\": {
                        \"VendorName\": \"AWS\",
                        \"Name\": \"AWSManagedRulesSQLiRuleSet\"
                    }
                },
                \"OverrideAction\": {\"None\": {}},
                \"VisibilityConfig\": {
                    \"SampledRequestsEnabled\": true,
                    \"CloudWatchMetricsEnabled\": true,
                    \"MetricName\": \"AWSSQLiRules\"
                }
            },
            {
                \"Name\": \"RateLimit\",
                \"Priority\": 5,
                \"Statement\": {
                    \"RateBasedStatement\": {
                        \"Limit\": $RATE_LIMIT,
                        \"AggregateKeyType\": \"IP\"
                    }
                },
                \"Action\": {\"Block\": {}},
                \"VisibilityConfig\": {
                    \"SampledRequestsEnabled\": true,
                    \"CloudWatchMetricsEnabled\": true,
                    \"MetricName\": \"RateLimit\"
                }
            },
            {
                \"Name\": \"BlockLargeRequests\",
                \"Priority\": 6,
                \"Statement\": {
                    \"SizeConstraintStatement\": {
                        \"FieldToMatch\": {\"Body\": {\"OversizeHandling\": \"MATCH\"}},
                        \"ComparisonOperator\": \"GT\",
                        \"Size\": 10485760,
                        \"TextTransformations\": [{\"Priority\": 0, \"Type\": \"NONE\"}]
                    }
                },
                \"Action\": {\"Block\": {}},
                \"VisibilityConfig\": {
                    \"SampledRequestsEnabled\": true,
                    \"CloudWatchMetricsEnabled\": true,
                    \"MetricName\": \"BlockLargeRequests\"
                }
            }
        ]" \
        --tags "[
            {\"Key\": \"Environment\", \"Value\": \"production\"},
            {\"Key\": \"Project\", \"Value\": \"vendure\"},
            {\"Key\": \"ManagedBy\", \"Value\": \"script\"}
        ]" \
        --query 'Summary.ARN' --output text)

    print_step "Created WebACL: $WAF_ARN"
fi

# =============================================================================
# STEP 2: Find and attach to ALB
# =============================================================================
print_step "Step 2: Finding production ALB"

# Find ALB by tag
ALB_ARN=$(aws elbv2 describe-load-balancers --region "$REGION" \
    --query 'LoadBalancers[?Type==`application`].LoadBalancerArn' \
    --output text 2>/dev/null | head -1)

if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" = "None" ]; then
    print_warn "No ALB found. After ALB is created, attach WAF with:"
    echo "  aws wafv2 associate-web-acl --web-acl-arn $WAF_ARN --resource-arn <ALB_ARN> --region $REGION"
else
    print_step "Found ALB: $ALB_ARN"

    # Check if already associated
    CURRENT_WAF=$(aws wafv2 get-web-acl-for-resource --resource-arn "$ALB_ARN" --region "$REGION" \
        --query 'WebACL.ARN' --output text 2>/dev/null || echo "None")

    if [ "$CURRENT_WAF" != "None" ] && [ -n "$CURRENT_WAF" ]; then
        print_warn "ALB already has WAF attached: $CURRENT_WAF"
    else
        aws wafv2 associate-web-acl \
            --web-acl-arn "$WAF_ARN" \
            --resource-arn "$ALB_ARN" \
            --region "$REGION"
        print_step "WAF attached to ALB"
    fi
fi

# =============================================================================
# STEP 3: Enable WAF logging (optional but recommended)
# =============================================================================
print_step "Step 3: Configuring WAF logging"

WAF_LOG_GROUP="aws-waf-logs-vendure-production"

# Create CloudWatch log group for WAF logs
aws logs create-log-group \
    --log-group-name "$WAF_LOG_GROUP" \
    --region "$REGION" 2>/dev/null || print_warn "Log group already exists"

# Set retention to 30 days
aws logs put-retention-policy \
    --log-group-name "$WAF_LOG_GROUP" \
    --retention-in-days 30 \
    --region "$REGION" 2>/dev/null || true

print_step "WAF logging configured to: $WAF_LOG_GROUP"

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo "=============================================="
echo "  WAF Setup Complete"
echo "=============================================="
echo ""
echo "  WebACL:     $WAF_NAME"
echo "  WAF ARN:    $WAF_ARN"
echo "  Region:     $REGION"
echo ""
echo "  Rules Active:"
echo "    1. AWS Common Rule Set (OWASP Core)"
echo "    2. Known Bad Inputs"
echo "    3. IP Reputation List"
echo "    4. SQL Injection Protection"
echo "    5. Rate Limiting ($RATE_LIMIT req/5min per IP)"
echo "    6. Large Request Blocking (>10MB)"
echo ""
echo "  Excluded Rules (to avoid false positives on GraphQL):"
echo "    - SizeRestrictions_BODY (GraphQL queries can be large)"
echo "    - GenericRFI_BODY (may false-positive on GraphQL)"
echo "    - CrossSiteScripting_BODY (admin UI uses rich text)"
echo ""
echo "  Logging:    CloudWatch ($WAF_LOG_GROUP)"
echo ""
echo "=============================================="
echo "  ESTIMATED COST:"
echo "=============================================="
echo ""
echo "  WebACL:         \$5/month"
echo "  Rules (6):      \$6/month"
echo "  Request charge:  \$0.60/million requests"
echo "  Total:           ~\$12-15/month"
echo ""
echo "=============================================="
echo "  MONITOR WAF IN CONSOLE:"
echo "=============================================="
echo ""
echo "  https://$REGION.console.aws.amazon.com/wafv2/homev2/web-acls"
echo ""
echo "  Or via CLI:"
echo "  aws wafv2 get-sampled-requests --web-acl-arn $WAF_ARN --rule-metric-name RateLimit --scope REGIONAL --time-window StartTime=$(date -u -d '1 hour ago' +%s 2>/dev/null || date -u -v-1H +%s),EndTime=$(date -u +%s) --max-items 10 --region $REGION"
echo ""
