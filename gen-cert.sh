#!/bin/bash
#
# gen-cert.sh - Generate S/MIME certificates with user-provided CN and validity period
#
# Usage: gen-cert.sh --cn <name> --days <period>
#

set -e

# Default paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSSL_CONF="${SCRIPT_DIR}/smime.cnf"
CA_KEY="${SCRIPT_DIR}/ca.key"
CA_CRT="${SCRIPT_DIR}/ca.crt"

# Output files
KEY_FILE="${SCRIPT_DIR}/key.pem"
CRT_FILE="${SCRIPT_DIR}/cert.pem"
P12_FILE="${SCRIPT_DIR}/pkcs12.p12"

# Default values
CN=""
DAYS=365

# Function to display help
show_help() {
    cat << EOF
Usage: gen-cert.sh --cn <name> --days <period>

Generate S/MIME certificates with user-provided Common Name and validity period.

Options:
  --cn       Common name for the certificate (required)
  --days     Validity period in days (required)
  --help     Show this help message

Output Files:
  key.pem    - Private key in PEM format
  cert.pem   - Signed certificate in PEM format
  pkcs12.p12 - PKCS#12 bundle containing both

Example:
  gen-cert.sh --cn "john@example.com" --days 365
EOF
    exit 0
}

# Function to log errors only
log_error() {
    echo "ERROR: $1" >&2
}

# Function to log info messages
log_info() {
    echo "$1"
}

# Function to check prerequisites
check_prerequisites() {
    # Check if OpenSSL is available
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not installed or not in PATH"
        exit 1
    fi

    # Check if smime.cnf exists
    if [[ ! -f "${OPENSSL_CONF}" ]]; then
        log_error "smime.cnf not found in ${SCRIPT_DIR}"
        exit 1
    fi

    # Check for CA files (create if missing)
    if [[ ! -f "${CA_KEY}" ]] || [[ ! -f "${CA_CRT}" ]]; then
        log_info "Generating CA certificate..."
        export OPENSSL_CONF="${SCRIPT_DIR}/smime.cnf"
        openssl genrsa -out "${CA_KEY}" 4096
        openssl req -new -x509 -days 3650 -key "${CA_KEY}" -out "${CA_CRT}" \
            -extensions v3_ca -config "${OPENSSL_CONF}" -quiet
    fi
}

# Function to parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cn)
                CN="$2"
                shift 2
                ;;
            --days)
                DAYS="$2"
                shift 2
                ;;
            --help)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information" >&2
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "${CN}" ]]; then
        log_error "--cn (common name) is required"
        exit 1
    fi

    if [[ -z "${DAYS}" ]] || ! [[ "${DAYS}" =~ ^[0-9]+$ ]]; then
        log_error "--days (validity period in days) is required and must be a number"
        exit 1
    fi
}

# Function to generate certificate
generate_certificate() {
    log_info "Generating 4096-bit RSA key..."
    openssl genrsa -out "${KEY_FILE}" 4096

    log_info "Generating Certificate Signing Request..."
    export OPENSSL_CONF="${SCRIPT_DIR}/smime.cnf"
    openssl req -new -key "${KEY_FILE}" -out "${SCRIPT_DIR}/cert.csr" \
        -subj "/CN=${CN}"

    log_info "Signing certificate with CA (${DAYS} days)..."
    openssl x509 -req -days "${DAYS}" -in "${SCRIPT_DIR}/cert.csr" \
        -CA "${CA_CRT}" -CAkey "${CA_KEY}" -set_serial 1 \
        -out "${CRT_FILE}" -addtrust emailProtection \
        -addreject clientAuth -addreject serverAuth -trustout \
        -extfile "${SCRIPT_DIR}/smime.cnf" -extensions smime

    log_info "Creating PKCS#12 bundle..."
    openssl pkcs12 -export -out "${P12_FILE}" -in "${CRT_FILE}" \
        -inkey "${KEY_FILE}" -passout pass:

    # Clean up temporary files
    rm -f "${SCRIPT_DIR}/cert.csr"
}

# Main function
main() {
    # Parse command line arguments
    parse_args "$@"

    # Check prerequisites
    check_prerequisites

    # Generate the certificate
    generate_certificate

    log_info "Certificate generation completed successfully!"
    log_info "Output files:"
    log_info "  - ${KEY_FILE}"
    log_info "  - ${CRT_FILE}"
    log_info "  - ${P12_FILE}"
}

# Run main function with all arguments
main "$@"
