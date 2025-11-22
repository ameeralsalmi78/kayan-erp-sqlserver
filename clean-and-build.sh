#!/bin/bash

echo "=========================================="
echo "KAYAN ERP - Clean Build Script"
echo "=========================================="
echo ""

echo "🧹 Cleaning problematic files..."

# حذف جميع الملفات بأسماء سيئة
find . -type f \( -name "*كيان*" -o -name "*نوفمبر*" -o -name "*ChatGPT*" -o -name "*kayan erp*" \) ! -path "*/node_modules/*" -delete 2>/dev/null

# حذف مجلدات dist و public القديمة
rm -rf dist public
mkdir -p public dist
echo "" > public/.gitkeep

echo "✅ Cleaning complete!"
echo ""

echo "🔨 Building project..."
npm run build > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo ""
    
    echo "/*    /index.html   200" > dist/_redirects
    
    # التحقق الصحيح
    python3 << 'PYCHECK'
import os
bad = []
for root, dirs, files in os.walk('dist'):
    for f in files:
        if any(ord(c) > 127 or c == ' ' for c in f if c != ' ' or f.endswith(('.jpg','.png'))):
            if any(ord(c) > 127 for c in f):
                bad.append(f)
            elif ' ' in f and f.endswith(('.jpg','.png','.gif')):
                bad.append(f)

if bad:
    print("❌ Problematic files:")
    for b in bad:
        print(f"  {b}")
else:
    print("✅ All files clean!")
    print("")
    print("="*50)
    print("🚀 READY TO DEPLOY - dist/ folder")
    print("="*50)
PYCHECK
    
    echo ""
    ls -lh dist/
else
    echo "❌ Build failed!"
    exit 1
fi
