#!/usr/bin/env bash
set -e

KEYSTORE_NAME="upload-keystore.jks"
ALIAS="upload"

echo "=========================================="
echo "  Android Release Keystore Generator     "
echo "=========================================="
echo ""

if ! command -v keytool &> /dev/null; then
    echo "Error: 'keytool' not found in PATH."
    echo "Please ensure Java JDK is installed."
    exit 1
fi

if [ -f "$KEYSTORE_NAME" ]; then
    read -p "Warning: '$KEYSTORE_NAME' already exists. Overwrite? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    rm -f "$KEYSTORE_NAME"
fi

read -s -p "Enter keystore password (min 6 chars): " PASSWORD
echo ""

if [ ${#PASSWORD} -lt 6 ]; then
    echo "Password must be at least 6 characters long."
    exit 1
fi

echo "Generating keystore: $KEYSTORE_NAME with alias '$ALIAS'..."

keytool -genkeypair -v \
    -keystore "$KEYSTORE_NAME" \
    -alias "$ALIAS" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -storetype PKCS12 \
    -storepass "$PASSWORD" \
    -keypass "$PASSWORD" \
    -dname "CN=Hridoy, OU=HridoyToolBox, O=Hridoy, L=Dhaka, ST=Dhaka, C=BD"

echo "[SUCCESS] Keystore created: $KEYSTORE_NAME"

# Base64 encode
if command -v base64 &> /dev/null; then
    base64 -w 0 "$KEYSTORE_NAME" > keystore_base64.txt 2>/dev/null || base64 "$KEYSTORE_NAME" > keystore_base64.txt
    echo "[SUCCESS] Base64 string saved to keystore_base64.txt"
fi

echo ""
echo "================================================================="
echo "  NEXT STEP: Add Secrets to GitHub Repository"
echo "================================================================="
echo "Go to: https://github.com/<your-username>/<your-repo>/settings/secrets/actions"
echo ""
echo "Add the following Repository Secrets:"
echo "  1. KEYSTORE_BASE64   -> Content of keystore_base64.txt"
echo "  2. KEYSTORE_PASSWORD -> The password you just entered"
echo "  3. KEY_ALIAS         -> $ALIAS"
echo "================================================================="

