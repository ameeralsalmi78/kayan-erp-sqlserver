#!/bin/bash

echo "================================"
echo "KAYAN ERP - Deployment Verification"
echo "================================"
echo ""

# Check for problematic files
echo "Checking for problematic filenames..."
problematic=$(find . -type f \( -name "*كيان*" -o -name "*نوفمبر*" -o -name "*ChatGPT*" -o -name "* *" \) ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null)

if [ -n "$problematic" ]; then
    echo "❌ FOUND PROBLEMATIC FILES:"
    echo "$problematic"
    exit 1
else
    echo "✅ No problematic files found"
fi

echo ""
echo "Listing all image files:"
find . \( -name "*.jpg" -o -name "*.png" \) ! -path "*/node_modules/*" ! -path "*/.git/*" | sort

echo ""
echo "================================"
echo "✅ DEPLOYMENT VERIFICATION PASSED"
echo "================================"
