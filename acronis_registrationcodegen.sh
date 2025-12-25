#!/bin/bash
#
# Acronis Registration Token Generator for MSPs
# Generates registration tokens for client organizations
#
# Usage: ./acronis_generate_tokens.sh
#

set -euo pipefail

# Configuration
CREDENTIALS_FILE="${HOME}/.config/acronis/credentials"
OUTPUT_FILE="./acronis_registrationkeys.json"
TEMP_DIR="/tmp/acronis_$$"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Cleanup on exit
trap 'rm -rf "$TEMP_DIR"' EXIT

# Create temp directory
mkdir -p "$TEMP_DIR"

# ============================================================================
# Functions
# ============================================================================

print_header() {
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_info() {
    echo -e "${BLUE}→${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# ============================================================================
# Credential Management
# ============================================================================

setup_credentials() {
    local cred_dir=$(dirname "$CREDENTIALS_FILE")
    
    print_header "Acronis API Credentials Setup"
    
    if [ -f "$CREDENTIALS_FILE" ]; then
        echo -e "Existing credentials found at: ${CYAN}$CREDENTIALS_FILE${NC}"
        read -p "Do you want to use existing credentials? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi
    
    # Create directory if it doesn't exist
    mkdir -p "$cred_dir"
    
    echo ""
    echo "Please enter your Acronis API credentials."
    echo "These will be stored securely at: $CREDENTIALS_FILE"
    echo ""
    
    # Get datacenter URL
    echo "Select your datacenter:"
    echo "  1) US (https://us-cloud.acronis.com)"
    echo "  2) EU (https://eu-cloud.acronis.com)"
    echo "  3) EU2 (https://eu2-cloud.acronis.com)"
    echo "  4) APAC (https://ap-cloud.acronis.com)"
    echo "  5) Custom"
    read -p "Enter choice [1-5]: " dc_choice
    
    case $dc_choice in
        1) DATACENTER_URL="https://us-cloud.acronis.com" ;;
        2) DATACENTER_URL="https://eu-cloud.acronis.com" ;;
        3) DATACENTER_URL="https://eu2-cloud.acronis.com" ;;
        4) DATACENTER_URL="https://ap-cloud.acronis.com" ;;
        5) read -p "Enter datacenter URL: " DATACENTER_URL ;;
        *) print_error "Invalid choice"; exit 1 ;;
    esac
    
    # Get credentials
    read -p "Enter API Client ID: " CLIENT_ID
    read -sp "Enter API Client Secret: " CLIENT_SECRET
    echo ""
    
    # Validate credentials
    print_info "Validating credentials..."
    
    local encoded_creds=$(echo -n "${CLIENT_ID}:${CLIENT_SECRET}" | base64)
    local token_response=$(curl -s -w "\n%{http_code}" -X POST "${DATACENTER_URL}/api/2/idp/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "Authorization: Basic ${encoded_creds}" \
        -d "grant_type=client_credentials")
    
    local http_code=$(echo "$token_response" | tail -n1)
    local response_body=$(echo "$token_response" | sed '$d')
    
    if [ "$http_code" -ne 200 ]; then
        print_error "Invalid credentials or datacenter URL"
        echo "Response: $response_body" | jq '.' 2>/dev/null || echo "$response_body"
        exit 1
    fi
    
    print_success "Credentials validated successfully"
    
    # Save credentials
    cat > "$CREDENTIALS_FILE" <<EOF
DATACENTER_URL="$DATACENTER_URL"
CLIENT_ID="$CLIENT_ID"
CLIENT_SECRET="$CLIENT_SECRET"
EOF
    
    # Set secure permissions
    chmod 600 "$CREDENTIALS_FILE"
    
    print_success "Credentials saved to $CREDENTIALS_FILE"
    echo ""
}

load_credentials() {
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        print_error "Credentials file not found: $CREDENTIALS_FILE"
        setup_credentials
    fi
    
    # shellcheck source=/dev/null
    source "$CREDENTIALS_FILE"
    
    if [ -z "${DATACENTER_URL:-}" ] || [ -z "${CLIENT_ID:-}" ] || [ -z "${CLIENT_SECRET:-}" ]; then
        print_error "Invalid credentials file"
        setup_credentials
        # shellcheck source=/dev/null
        source "$CREDENTIALS_FILE"
    fi
}

# ============================================================================
# API Functions
# ============================================================================

get_access_token() {
    print_info "Authenticating to Acronis API..."
    
    local encoded_creds=$(echo -n "${CLIENT_ID}:${CLIENT_SECRET}" | base64)
    
    local token_response=$(curl -s -w "\n%{http_code}" -X POST "${DATACENTER_URL}/api/2/idp/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "Authorization: Basic ${encoded_creds}" \
        -d "grant_type=client_credentials")
    
    local http_code=$(echo "$token_response" | tail -n1)
    local response_body=$(echo "$token_response" | sed '$d')
    
    if [ "$http_code" -ne 200 ]; then
        print_error "Failed to get access token (HTTP $http_code)"
        echo "$response_body" | jq '.' 2>/dev/null || echo "$response_body"
        exit 1
    fi
    
    ACCESS_TOKEN=$(echo "$response_body" | jq -r '.access_token')
    TENANT_ID=$(echo "$response_body" | jq -r '.tenant_id // empty')
    
    if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" == "null" ]; then
        print_error "Failed to extract access token"
        exit 1
    fi
    
    print_success "Authentication successful"
}

get_client_tenants() {
    print_info "Fetching client organizations..."
    
    local response=$(curl -s -w "\n%{http_code}" -X GET \
        "${DATACENTER_URL}/api/2/tenants?kind=customer" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}")
    
    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -ne 200 ]; then
        print_error "Failed to fetch tenants (HTTP $http_code)"
        echo "$response_body" | jq '.' 2>/dev/null || echo "$response_body"
        exit 1
    fi
    
    echo "$response_body" | jq -r '.items[] | select(.kind == "customer") | {id: .id, name: .name, contact_email: .contact.email}' | \
        jq -s '.' > "$TEMP_DIR/clients.json"
    
    local client_count=$(jq 'length' "$TEMP_DIR/clients.json")
    
    if [ "$client_count" -eq 0 ]; then
        print_error "No client organizations found"
        exit 1
    fi
    
    print_success "Found $client_count client organization(s)"
}

display_clients() {
    print_header "Available Client Organizations"
    
    local total=$(jq 'length' "$TEMP_DIR/clients.json")
    
    echo ""
    printf "${CYAN}%-6s %-40s %-30s${NC}\n" "NUM" "ORGANIZATION NAME" "CONTACT EMAIL"
    printf "${CYAN}%-6s %-40s %-30s${NC}\n" "---" "------------------------------------" "-----------------------------"
    
    for i in $(seq 0 $((total - 1))); do
        local name=$(jq -r ".[$i].name" "$TEMP_DIR/clients.json")
        local email=$(jq -r ".[$i].contact_email // \"N/A\"" "$TEMP_DIR/clients.json")
        printf "%-6s %-40s %-30s\n" "$((i + 1))" "${name:0:40}" "${email:0:30}"
    done
    
    echo ""
    echo -e "${YELLOW}Total: $total client(s)${NC}"
    echo ""
}

parse_selection() {
    local input="$1"
    local max="$2"
    local -a indices=()
    
    # Handle range (e.g., "1-5" or "10-20")
    if [[ "$input" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        
        if [ "$start" -lt 1 ] || [ "$end" -gt "$max" ] || [ "$start" -gt "$end" ]; then
            print_error "Invalid range. Must be between 1 and $max, with start <= end"
            return 1
        fi
        
        for i in $(seq "$start" "$end"); do
            indices+=($((i - 1)))
        done
    # Handle comma-separated list (e.g., "1,3,5")
    elif [[ "$input" =~ ^[0-9,]+$ ]]; then
        IFS=',' read -ra NUMS <<< "$input"
        for num in "${NUMS[@]}"; do
            if [ "$num" -lt 1 ] || [ "$num" -gt "$max" ]; then
                print_error "Invalid number: $num. Must be between 1 and $max"
                return 1
            fi
            indices+=($((num - 1)))
        done
    # Handle single number
    elif [[ "$input" =~ ^[0-9]+$ ]]; then
        if [ "$input" -lt 1 ] || [ "$input" -gt "$max" ]; then
            print_error "Invalid number. Must be between 1 and $max"
            return 1
        fi
        indices+=($((input - 1)))
    # Handle "all"
    elif [ "$input" == "all" ]; then
        for i in $(seq 0 $((max - 1))); do
            indices+=($i)
        done
    else
        print_error "Invalid input. Use a number (5), range (1-10), comma-separated (1,3,5), or 'all'"
        return 1
    fi
    
    # Return indices as space-separated string
    echo "${indices[@]}"
}

create_registration_token() {
    local tenant_id="$1"
    local tenant_name="$2"
    local expires_days="${3:-3}"
    
    local expires_in=$((expires_days * 24 * 60 * 60))
    
    local response=$(curl -s -w "\n%{http_code}" -X POST \
        "${DATACENTER_URL}/api/2/tenants/${tenant_id}/registration_tokens" \
        -H "Authorization: Bearer ${ACCESS_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"expires_in\": ${expires_in},
            \"scopes\": [\"urn:acronis.com:tenant-id::backup_agent_admin\"]
        }")
    
    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" -ne 200 ]; then
        print_error "Failed to create token for: $tenant_name (HTTP $http_code)"
        echo "$response_body" | jq '.' 2>/dev/null || echo "$response_body"
        return 1
    fi
    
    local token=$(echo "$response_body" | jq -r '.token')
    
    if [ -z "$token" ] || [ "$token" == "null" ]; then
        print_error "Failed to extract token for: $tenant_name"
        return 1
    fi
    
    echo "$token"
}

# ============================================================================
# Main Script
# ============================================================================

main() {
    clear
    print_header "Acronis Registration Token Generator"
    
    # Check dependencies
    if ! command -v jq &> /dev/null; then
        print_error "This script requires 'jq' to be installed"
        echo "Install with: sudo apt install jq"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        print_error "This script requires 'curl' to be installed"
        exit 1
    fi
    
    # Load or setup credentials
    load_credentials
    
    # Authenticate
    get_access_token
    
    # Get client list
    get_client_tenants
    
    # Display clients
    display_clients
    
    # Get selection
    local total=$(jq 'length' "$TEMP_DIR/clients.json")
    echo "Select client(s) to generate tokens for:"
    echo "  - Single: 5"
    echo "  - Range: 1-10"
    echo "  - Multiple: 1,5,10"
    echo "  - All: all"
    echo ""
    read -p "Enter selection: " selection
    
    # Parse selection
    local indices=$(parse_selection "$selection" "$total") || exit 1
    local indices_array=($indices)
    local count=${#indices_array[@]}
    
    echo ""
    print_info "Generating tokens for $count client(s)..."
    
    # Get token expiration
    echo ""
    read -p "Token expiration in days [default: 3]: " expires_days
    expires_days=${expires_days:-3}
    
    if ! [[ "$expires_days" =~ ^[0-9]+$ ]] || [ "$expires_days" -lt 1 ]; then
        print_error "Invalid expiration days. Using default: 3"
        expires_days=3
    fi
    
    echo ""
    print_header "Generating Registration Tokens"
    
    # Initialize output JSON
    echo "[]" > "$TEMP_DIR/output.json"
    
    local success_count=0
    local fail_count=0
    
    for idx in "${indices_array[@]}"; do
        local tenant_id=$(jq -r ".[$idx].id" "$TEMP_DIR/clients.json")
        local tenant_name=$(jq -r ".[$idx].name" "$TEMP_DIR/clients.json")
        local tenant_email=$(jq -r ".[$idx].contact_email // \"N/A\"" "$TEMP_DIR/clients.json")
        
        printf "%-40s ... " "${tenant_name:0:37}"
        
        if token=$(create_registration_token "$tenant_id" "$tenant_name" "$expires_days"); then
            print_success "OK"
            
            # Add to output
            local entry=$(jq -n \
                --arg name "$tenant_name" \
                --arg id "$tenant_id" \
                --arg email "$tenant_email" \
                --arg token "$token" \
                --arg expires "$expires_days" \
                --arg datacenter "$DATACENTER_URL" \
                '{
                    organization_name: $name,
                    tenant_id: $id,
                    contact_email: $email,
                    registration_token: $token,
                    expires_days: ($expires | tonumber),
                    datacenter_url: $datacenter,
                    created_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
                }')
            
            jq --argjson entry "$entry" '. += [$entry]' "$TEMP_DIR/output.json" > "$TEMP_DIR/output.tmp.json"
            mv "$TEMP_DIR/output.tmp.json" "$TEMP_DIR/output.json"
            
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    # Save output file
    cp "$TEMP_DIR/output.json" "$OUTPUT_FILE"
    
    echo ""
    print_header "Summary"
    echo ""
    print_success "Successfully generated: $success_count token(s)"
    if [ "$fail_count" -gt 0 ]; then
        print_error "Failed to generate: $fail_count token(s)"
    fi
    echo ""
    print_success "Tokens saved to: ${CYAN}$OUTPUT_FILE${NC}"
    echo ""
    
    # Display usage example
    if [ "$success_count" -gt 0 ]; then
        print_header "Usage Example"
        echo ""
        
        local first_token=$(jq -r '.[0].registration_token' "$OUTPUT_FILE")
        local first_org=$(jq -r '.[0].organization_name' "$OUTPUT_FILE")
        
        echo "For: $first_org"
        echo ""
        echo -e "${YELLOW}Linux/Proxmox:${NC}"
        echo "  ./acronis_agent_x86_64.sh --quiet --registration by-token \\"
        echo "    --reg-token \"$first_token\" \\"
        echo "    --reg-address \"$DATACENTER_URL\""
        echo ""
        echo -e "${YELLOW}Windows:${NC}"
        echo "  .\\Cyber_Protection_Agent_for_Windows_x64.exe --quiet --registration by-token \\"
        echo "    --reg-token \"$first_token\" \\"
        echo "    --reg-address \"$DATACENTER_URL\""
        echo ""
    fi
    
    # Offer to display JSON
    read -p "Display full JSON output? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        jq '.' "$OUTPUT_FILE"
    fi
    
    echo ""
    print_info "Done!"
}

# Run main function
main "$@"
