#!/bin/bash

#########################################################
# سكريبت تحميل KAYAN ERP - SQL Server Version
# Download Script for KAYAN ERP with SQL Server support
#########################################################

echo "╔══════════════════════════════════════════════════════╗"
echo "║      KAYAN ERP - سكريبت التحميل                     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

SOURCE_PATH="/tmp/cc-agent/54831328/kayan-erp-sqlserver.tar.gz"
DEST_PATH="$HOME/Downloads/kayan-erp-sqlserver.tar.gz"

# تحقق من وجود الملف المصدر
if [ ! -f "$SOURCE_PATH" ]; then
    echo "❌ الملف المصدر غير موجود!"
    echo "📍 المسار المتوقع: $SOURCE_PATH"
    exit 1
fi

# أنشئ مجلد Downloads إذا لم يكن موجوداً
mkdir -p "$HOME/Downloads"

# انسخ الملف
echo "📥 جاري نسخ الملف..."
cp "$SOURCE_PATH" "$DEST_PATH"

if [ $? -eq 0 ]; then
    echo "✅ تم التحميل بنجاح!"
    echo ""
    echo "📁 الملف موجود في:"
    echo "   $DEST_PATH"
    echo ""
    echo "💾 حجم الملف: $(du -h "$DEST_PATH" | cut -f1)"
    echo ""
    echo "🎯 الخطوة التالية:"
    echo "   cd ~/Downloads"
    echo "   tar -xzf kayan-erp-sqlserver.tar.gz"
    echo "   cd project"
    echo "   cat SQL_SERVER_SUMMARY.txt"
else
    echo "❌ فشل النسخ!"
    exit 1
fi
