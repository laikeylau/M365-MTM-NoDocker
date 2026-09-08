#!/bin/bash
# Generate self-signed SSL certificates for development
# For production, use Let's Encrypt or your own certificates

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSL_DIR="$SCRIPT_DIR/ssl"

mkdir -p "$SSL_DIR"

DOMAIN="${DOMAIN:-localhost}"

echo "Generating self-signed SSL certificate for: $DOMAIN"

openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout "$SSL_DIR/key.pem" \
    -out "$SSL_DIR/cert.pem" \
    -subj "/CN=$DOMAIN" \
    -addext "subjectAltName=DNS:$DOMAIN,DNS:localhost,IP:127.0.0.1"

echo "SSL certificates generated:"
echo "  Certificate: $SSL_DIR/cert.pem"
echo "  Key: $SSL_DIR/key.pem"
echo ""
echo "For production, replace these with real certificates."
