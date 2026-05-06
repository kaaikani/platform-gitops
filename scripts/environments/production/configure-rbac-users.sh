#!/bin/bash
# =============================================================================
# RBAC USERS CONFIGURATION SCRIPT (ENHANCED)
# =============================================================================
# This script helps configure RBAC users in the Vendure Helm values
# Features:
#   - Automatically fetches IAM users
#   - Automatically fetches EKS access entries
#   - Interactive user selection and role assignment
#   - Optionally updates values file automatically
#
# Usage:
#   chmod +x configure-rbac-users.sh
#   ./configure-rbac-users.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_step() { echo -e "${GREEN}▶ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_info() { echo -e "${CYAN}ℹ $1${NC}"; }

VALUES_FILE="vendure-values.yaml"
CLUSTER_NAME="${CLUSTER_NAME:-vendure-prod}"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Arrays to store users
declare -a IAM_USERS
declare -a EKS_ACCESS_ENTRIES
declare -a DEVELOPERS
declare -a DEVOPS
declare -a READONLY

# =============================================================================
# FETCH IAM USERS
# =============================================================================
fetch_iam_users() {
    print_step "Fetching IAM users..."
    
    if ! command -v aws &>/dev/null; then
        print_warning "AWS CLI not found, skipping IAM users"
        return
    fi
    
    if aws iam list-users --query 'Users[*].UserName' --output text 2>/dev/null > "$TEMP_DIR/iam_users.txt"; then
        # Read users line by line, handling space-separated output
        while IFS=$'\t' read -r -a users_array; do
            for user in "${users_array[@]}"; do
                if [ -n "$user" ]; then
                    IAM_USERS+=("$user")
                fi
            done
        done < "$TEMP_DIR/iam_users.txt"
        # Also try reading as space-separated if tab didn't work
        if [ ${#IAM_USERS[@]} -eq 0 ]; then
            while IFS=' ' read -r -a users_array; do
                for user in "${users_array[@]}"; do
                    if [ -n "$user" ]; then
                        IAM_USERS+=("$user")
                    fi
                done
            done < "$TEMP_DIR/iam_users.txt"
        fi
        
        if [ ${#IAM_USERS[@]} -gt 0 ]; then
            print_success "Found ${#IAM_USERS[@]} IAM user(s)"
        else
            print_warning "No IAM users found"
        fi
    else
        print_warning "Failed to fetch IAM users (check AWS credentials)"
    fi
}

# =============================================================================
# FETCH EKS ACCESS ENTRIES
# =============================================================================
fetch_eks_access_entries() {
    print_step "Fetching EKS access entries..."
    
    if ! command -v aws &>/dev/null; then
        print_warning "AWS CLI not found, skipping EKS access entries"
        return
    fi
    
    if aws eks list-access-entries --cluster-name "$CLUSTER_NAME" \
        --query 'accessEntries[*]' --output text 2>/dev/null > "$TEMP_DIR/eks_entries.txt"; then
        while IFS= read -r entry; do
            if [ -n "$entry" ]; then
                EKS_ACCESS_ENTRIES+=("$entry")
            fi
        done < "$TEMP_DIR/eks_entries.txt"
        
        if [ ${#EKS_ACCESS_ENTRIES[@]} -gt 0 ]; then
            print_success "Found ${#EKS_ACCESS_ENTRIES[@]} EKS access entr(ies)"
        else
            print_warning "No EKS access entries found (may use aws-auth ConfigMap)"
        fi
    else
        print_warning "Failed to fetch EKS access entries (cluster may not exist or use aws-auth)"
    fi
}

# =============================================================================
# DISPLAY AVAILABLE USERS
# =============================================================================
display_users() {
    print_header "Available Users"
    
    local all_users=()
    local index=1
    
    # Add IAM users
    if [ ${#IAM_USERS[@]} -gt 0 ]; then
        echo ""
        echo -e "${CYAN}IAM Users:${NC}"
        for user in "${IAM_USERS[@]}"; do
            echo "  [$index] $user (IAM)"
            all_users+=("$user")
            ((index++))
        done
    fi
    
    # Add EKS access entries
    if [ ${#EKS_ACCESS_ENTRIES[@]} -gt 0 ]; then
        echo ""
        echo -e "${CYAN}EKS Access Entries:${NC}"
        for entry in "${EKS_ACCESS_ENTRIES[@]}"; do
            echo "  [$index] $entry (EKS)"
            all_users+=("$entry")
            ((index++))
        done
    fi
    
    # If no users found, allow manual entry
    if [ ${#all_users[@]} -eq 0 ]; then
        echo ""
        print_warning "No users found automatically"
        echo "You can enter usernames manually"
        echo ""
    fi
    
    echo "${all_users[@]}"
}

# =============================================================================
# INTERACTIVE USER SELECTION
# =============================================================================
select_users_for_role() {
    local role_name=$1
    local role_description=$2
    local -n result_array=$3  # Use nameref to return array
    
    print_header "Configure $role_name"
    echo ""
    echo "$role_description"
    echo ""
    
    # Get all available users
    local all_users=("${IAM_USERS[@]}" "${EKS_ACCESS_ENTRIES[@]}")
    
    if [ ${#all_users[@]} -eq 0 ]; then
        echo "Enter usernames manually (one per line, empty line to finish):"
        while IFS= read -r user; do
            [ -z "$user" ] && break
            result_array+=("$user")
        done
    else
        echo "Select users for $role_name:"
        echo "  • Enter numbers separated by spaces (e.g., 1 3 5)"
        echo "  • Or type username directly (e.g., devops@kk)"
        echo "  • Or type 'skip' to skip this role"
        echo ""
        for i in "${!all_users[@]}"; do
            echo "  [$((i+1))] ${all_users[$i]}"
        done
        echo ""
        read -p "Selection: " selection
        
        if [[ "$selection" == "skip" ]] || [ -z "$selection" ]; then
            return
        fi
        
        # Check if selection is a username (contains @ or doesn't match number pattern)
        if [[ "$selection" =~ @ ]] || [[ ! "$selection" =~ ^[0-9\ ]+$ ]]; then
            # Direct username input
            if [[ " ${all_users[@]} " =~ " ${selection} " ]]; then
                result_array+=("$selection")
                print_success "Added user: $selection"
            else
                print_warning "User '$selection' not found in list, but adding anyway"
                result_array+=("$selection")
            fi
        else
            # Number selection
            for num in $selection; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le ${#all_users[@]} ]; then
                    result_array+=("${all_users[$((num-1))]}")
                fi
            done
        fi
    fi
}

# =============================================================================
# UPDATE VALUES FILE
# =============================================================================
update_values_file() {
    print_header "Updating $VALUES_FILE"
    
    if [ ! -f "$VALUES_FILE" ]; then
        print_error "Values file not found: $VALUES_FILE"
        return 1
    fi
    
    # Create backup
    cp "$VALUES_FILE" "$VALUES_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    print_step "Backup created: $VALUES_FILE.backup.*"
    
    # Create temporary file with updated RBAC section
    local in_rbac=false
    local rbac_done=false
    local temp_file="$TEMP_DIR/values_updated.yaml"
    
    while IFS= read -r line || [ -n "$line" ]; do
        # Detect RBAC section start
        if [[ "$line" =~ ^rbac: ]]; then
            in_rbac=true
            rbac_done=false
            echo "$line" >> "$temp_file"
            continue
        fi
        
        # If in RBAC section and haven't written it yet
        if [ "$in_rbac" = true ] && [ "$rbac_done" = false ]; then
            # Skip existing RBAC content until we hit next top-level key
            if [[ "$line" =~ ^[a-zA-Z] ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
                # Next top-level key, write RBAC config and continue
                echo "  enabled: true" >> "$temp_file"
                echo "" >> "$temp_file"
                echo "  # Developers - Read-only access" >> "$temp_file"
                echo "  developers:" >> "$temp_file"
                if [ ${#DEVELOPERS[@]} -gt 0 ]; then
                    for user in "${DEVELOPERS[@]}"; do
                        echo "    - $user" >> "$temp_file"
                    done
                else
                    echo "    # - developer1" >> "$temp_file"
                fi
                echo "" >> "$temp_file"
                echo "  # DevOps - Full access" >> "$temp_file"
                echo "  devops:" >> "$temp_file"
                if [ ${#DEVOPS[@]} -gt 0 ]; then
                    for user in "${DEVOPS[@]}"; do
                        echo "    - $user" >> "$temp_file"
                    done
                else
                    echo "    # - devops1" >> "$temp_file"
                fi
                echo "" >> "$temp_file"
                echo "  # Read-only users" >> "$temp_file"
                echo "  readOnly:" >> "$temp_file"
                if [ ${#READONLY[@]} -gt 0 ]; then
                    for user in "${READONLY[@]}"; do
                        echo "    - $user" >> "$temp_file"
                    done
                else
                    echo "    # - manager1" >> "$temp_file"
                fi
                rbac_done=true
                in_rbac=false
                echo "$line" >> "$temp_file"
            fi
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$VALUES_FILE"
    
    # If RBAC section wasn't found, append it
    if [ "$rbac_done" = false ]; then
        echo "" >> "$temp_file"
        echo "# =============================================================================" >> "$temp_file"
        echo "# RBAC (Role-Based Access Control)" >> "$temp_file"
        echo "# =============================================================================" >> "$temp_file"
        echo "rbac:" >> "$temp_file"
        echo "  enabled: true" >> "$temp_file"
        echo "  developers:" >> "$temp_file"
        for user in "${DEVELOPERS[@]}"; do
            echo "    - $user" >> "$temp_file"
        done
        echo "  devops:" >> "$temp_file"
        for user in "${DEVOPS[@]}"; do
            echo "    - $user" >> "$temp_file"
        done
        echo "  readOnly:" >> "$temp_file"
        for user in "${READONLY[@]}"; do
            echo "    - $user" >> "$temp_file"
        done
    fi
    
    # Replace original file
    mv "$temp_file" "$VALUES_FILE"
    print_success "Values file updated!"
}

# =============================================================================
# MAIN CONFIGURATION
# =============================================================================
main() {
    print_header "RBAC Users Configuration (Enhanced)"
    
    echo ""
    echo "This script will:"
    echo "  1. Fetch IAM users and EKS access entries"
    echo "  2. Let you assign users to roles interactively"
    echo "  3. Update $VALUES_FILE automatically"
    echo ""
    echo "RBAC Roles Available:"
    echo "  • developer-role: Read-only access (view pods, logs, deployments)"
    echo "  • devops-role: Full access to application resources (can modify)"
    echo "  • read-only-role: View-only access (cannot modify anything)"
    echo ""
    
    read -p "Continue? (y/n): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Aborted"
        exit 0
    fi
    
    # Fetch users
    fetch_iam_users
    fetch_eks_access_entries
    
    # Display available users
    display_users
    
    # Configure each role
    echo ""
    read -p "Press Enter to start role assignment..."
    
    # Developers
    select_users_for_role "Developers" "Assign users to developer-role (read-only access)" DEVELOPERS
    
    # DevOps
    select_users_for_role "DevOps" "Assign users to devops-role (full access)" DEVOPS
    
    # Read-only
    select_users_for_role "Read-Only" "Assign users to read-only-role (view-only access)" READONLY
    
    # Summary
    print_header "Configuration Summary"
    echo ""
    echo "Developers (${#DEVELOPERS[@]}): ${DEVELOPERS[*]}"
    echo "DevOps (${#DEVOPS[@]}): ${DEVOPS[*]}"
    echo "Read-only (${#READONLY[@]}): ${READONLY[*]}"
    echo ""
    
    read -p "Update $VALUES_FILE with this configuration? (y/n): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        update_values_file
        
        print_header "Next Steps"
        echo ""
        echo "1. Review the updated $VALUES_FILE"
        echo "2. Upgrade Helm release:"
        echo ""
        echo "   helm upgrade vendure-stack ../../vendure-stack \\"
        echo "     -f $VALUES_FILE \\"
        echo "     -n vendure-production"
        echo ""
        echo "3. Verify RBAC:"
        echo "   kubectl get roles -n vendure-production"
        echo "   kubectl get rolebindings -n vendure-production"
        echo ""
    else
        print_warning "Values file not updated"
        echo ""
        echo "You can manually edit $VALUES_FILE and add:"
        echo "  rbac:"
        echo "    enabled: true"
        echo "    developers:"
        for user in "${DEVELOPERS[@]}"; do
            echo "      - $user"
        done
        echo "    devops:"
        for user in "${DEVOPS[@]}"; do
            echo "      - $user"
        done
        echo "    readOnly:"
        for user in "${READONLY[@]}"; do
            echo "      - $user"
        done
    fi
}

main "$@"

