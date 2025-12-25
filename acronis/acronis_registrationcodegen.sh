#!/bin/bash
#
# Acronis Registration Token Generator for MSPs
# Generates registration tokens for client organizations
#
# FIX: Updated to use correct API endpoints:
#      1. Get partner tenant ID from /clients/{client_id}
#      2. Use /tenants/{tenant_id}/children to list customer tenants
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

CREDENTIALS_FILE="${HOME}/.config/acronis/credentials"
OUTPUT_FILE="./acronis_registrationkeys.json"
TEMP_DIR="/tmp/acronis_$$"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

trap 'rm -rf "$TEMP_DIR"' EXIT
mkdir -p "$TEMP_DIR"

# ============================================================================
# Output helpers
# ============================================================================

print_header() {
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1" >&2; }
print_info()    { echo -e "${BLUE}→${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }

# ============================================================================
# Credential Management
# ============================================================================

setup_credentials() {
    local cred_dir
    cred_dir=$(dirname "$CREDENTIALS_FILE")

    print_header "Acronis API Credentials Setup"

    mkdir -p "$cred_dir"

    echo ""
    echo "Select your datacenter:"
    echo "  1) US (us15)"
    echo "  2) US2 (us2)"
    echo "  3) US3 (us3)"
    echo "  4) EU (eu)"
    echo "  5) EU2 (eu2)"
    echo "  6) EU8 (eu8)"
    echo "  7) APAC (ap)"
    echo "  8) Custom"
    read -p "Enter choice [1-8]: " dc_choice

    case $dc_choice in
        1)
            DATACENTER_URL="https://us15-cloud.acronis.com"
            ;;
        2)
            DATACENTER_URL="https://us2-cloud.acronis.com"
            ;;
        3)
            DATACENTER_URL="https://us3-cloud.acronis.com"
            ;;
        4)
            DATACENTER_URL="https://eu-cloud.acronis.com"
            ;;
        5)
            DATACENTER_URL="https://eu2-cloud.acronis.com"
            ;;
        6)
            DATACENTER_URL="https://eu8-cloud.acronis.com"
            ;;
        7)
            DATACENTER_URL="https://ap-cloud.acronis.com"
            ;;
        8)
            read -p "Enter DATACENTER URL: " DATACENTER_URL
            ;;
        *)
            print_error "Invalid selection"
            exit 1
            ;;
    esac

    echo ""
    read -p "Enter API Client ID: " CLIENT_ID
    read -sp "Enter API Client Secret: " CLIENT_SECRET
    echo ""

    print_info "Validating credentials..."

    # FIXED: Added -w 0 to prevent base64 from adding newlines
    local basic_auth
    basic_auth=$(echo -n "${CLIENT_ID}:${CLIENT_SECRET}" | base64 -w 0)

    local response http body
    response=$(curl -s -w "\n%{http_code}" -X POST \
        "${DATACENTER_URL}/api/2/idp/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "Authorization: Basic ${basic_auth}" \
        -d "grant_type=client_credentials")

    http=$(tail -n1 <<<"$response")
    body=$(sed '$d' <<<"$response")

    if [[ "$http" != "200" ]]; then
        print_error "Credential validation failed"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        exit 1
    fi

    print_success "Credentials validated"

    cat > "$CREDENTIALS_FILE" <<EOF
DATACENTER_URL="$DATACENTER_URL"
CLIENT_ID="$CLIENT_ID"
CLIENT_SECRET="$CLIENT_SECRET"
EOF

    chmod 600 "$CREDENTIALS_FILE"
    print_success "Saved credentials to $CREDENTIALS_FILE"
}

load_credentials() {
    if [[ ! -f "$CREDENTIALS_FILE" ]]; then
        setup_credentials
    fi

    source "$CREDENTIALS_FILE"

    if [[ -z "${DATACENTER_URL:-}" || -z "${CLIENT_ID:-}" || -z "${CLIENT_SECRET:-}" ]]; then
        print_error "Incomplete credentials file"
        setup_credentials
        source "$CREDENTIALS_FILE"
    fi
}

# ============================================================================
# API Functions
# ============================================================================

get_access_token() {
    print_info "Authenticating to Acronis API..."

    # FIXED: Added -w 0 to prevent base64 from adding newlines
    local basic_auth
    basic_auth=$(echo -n "${CLIENT_ID}:${CLIENT_SECRET}" | base64 -w 0)

    local response http body
    response=$(curl -s -w "\n%{http_code}" -X POST \
        "${DATACENTER_URL}/api/2/idp/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "Authorization: Basic ${basic_auth}" \
        -d "grant_type=client_credentials")

    http=$(tail -n1 <<<"$response")
    body=$(sed '$d' <<<"$response")

    if [[ "$http" != "200" ]]; then
        print_error "Authentication failed"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        exit 1
    fi

    ACCESS_TOKEN=$(jq -r '.access_token' <<<"$body")

    if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
        print_error "Access token missing in response"
        exit 1
    fi

    print_success "Authentication successful"
}

get_partner_tenant_id() {
    print_info "Getting partner tenant ID..."

    local response http body
    response=$(curl -s -w "\n%{http_code}" -X GET \
        "${DATACENTER_URL}/api/2/clients/${CLIENT_ID}" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}")

    http=$(tail -n1 <<<"$response")
    body=$(sed '$d' <<<"$response")

    if [[ "$http" != "200" ]]; then
        print_error "Failed to get client info"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        exit 1
    fi

    PARTNER_TENANT_ID=$(jq -r '.tenant_id' <<<"$body")

    if [[ -z "$PARTNER_TENANT_ID" || "$PARTNER_TENANT_ID" == "null" ]]; then
        print_error "Tenant ID missing in response"
        exit 1
    fi

    print_success "Partner tenant ID: $PARTNER_TENANT_ID"
}

get_client_tenants() {
    print_info "Fetching client organizations..."

    local response http body
    response=$(curl -s -w "\n%{http_code}" -X GET \
        "${DATACENTER_URL}/api/2/tenants/${PARTNER_TENANT_ID}/children?include_details=true" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}")

    http=$(tail -n1 <<<"$response")
    body=$(sed '$d' <<<"$response")

    if [[ "$http" != "200" ]]; then
        print_error "Failed to fetch tenants"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        exit 1
    fi

    # Filter for customer tenants only
    echo "$body" | jq -r '.items[] | select(.kind=="customer") | {id:.id,name:.name,contact_email:.contact.email}' | jq -s '.' > "$TEMP_DIR/clients.json"

    local count
    count=$(jq 'length' "$TEMP_DIR/clients.json")

    [[ "$count" -gt 0 ]] || { print_error "No customer tenants found"; exit 1; }

    print_success "Found $count customer tenant(s)"
}

create_registration_token() {
    local tenant_id="$1"
    local expires_days="${2:-3}"
    local expires=$((expires_days * 86400))

    local response http body
    response=$(curl -s -w "\n%{http_code}" -X POST \
        "${DATACENTER_URL}/api/2/tenants/${tenant_id}/registration_tokens" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"expires_in\": ${expires},
            \"scopes\": [\"urn:acronis.com:tenant-id::backup_agent_admin\"]
        }")

    http=$(tail -n1 <<<"$response")
    body=$(sed '$d' <<<"$response")

    if [[ "$http" != "200" ]]; then
        echo "$body" > "$TEMP_DIR/error_${tenant_id}.json"
        return 1
    fi
    
    jq -r '.token' <<<"$body"
}

# ============================================================================
# Main
# ============================================================================

main() {
    clear
    print_header "Acronis Registration Token Generator"

    command -v jq >/dev/null || { print_error "jq is required"; exit 1; }
    command -v curl >/dev/null || { print_error "curl is required"; exit 1; }

    load_credentials
    get_access_token
    get_partner_tenant_id
    get_client_tenants

    print_header "Generating Tokens"
    echo "[]" > "$OUTPUT_FILE"

    local total
    total=$(jq 'length' "$TEMP_DIR/clients.json")

    for ((i=0; i<total; i++)); do
        tenant_id=$(jq -r ".[$i].id" "$TEMP_DIR/clients.json")
        tenant_name=$(jq -r ".[$i].name" "$TEMP_DIR/clients.json")

        printf "%-40s ... " "$tenant_name"

        if token=$(create_registration_token "$tenant_id"); then
            print_success "OK"
            jq --arg name "$tenant_name" --arg token "$token" \
               '. += [{organization:$name,registration_token:$token}]' \
               "$OUTPUT_FILE" > "$OUTPUT_FILE.tmp" && mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
        else
            print_error "FAILED"
            if [[ -f "$TEMP_DIR/error_${tenant_id}.json" ]]; then
                echo "    Error details:" >&2
                jq '.' "$TEMP_DIR/error_${tenant_id}.json" 2>/dev/null || cat "$TEMP_DIR/error_${tenant_id}.json"
            fi
        fi
    done

    print_success "Tokens saved to $OUTPUT_FILE"
}

main "$@"