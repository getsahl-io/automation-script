#!/bin/bash
# Simple test script for input validation

echo "Testing Account ID validation..."
echo ""

# Test function
test_account_id() {
    local input="$1"
    local clean_input=$(echo "$input" | tr -d '[:space:]')
    
    echo "Testing input: '$input'"
    echo "After cleanup: '$clean_input'"
    echo "Length: ${#clean_input}"
    
    if [[ ${#clean_input} -eq 12 ]] && [[ $clean_input =~ ^[0-9]+$ ]]; then
        echo "✓ VALID"
    else
        echo "✗ INVALID"
    fi
    echo "---"
}

# Test cases
test_account_id "123456789012"
test_account_id "040745305102"
test_account_id " 040745305102 "
test_account_id "abc123456789"
test_account_id "12345678901"
test_account_id "1234567890123"

echo ""
echo "Now try entering your Account ID manually:"
read -p "Enter AWS Account ID: " MANUAL_INPUT
test_account_id "$MANUAL_INPUT"
