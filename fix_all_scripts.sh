#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "正在修复脚本换行符问题..."
echo "脚本目录: $SCRIPT_DIR"

find "$SCRIPT_DIR" -type f -name "*.sh" -print0 | while IFS= read -r -d '' file; do
    if file "$file" | grep -q "CRLF"; then
        echo "修复: $file"
        sed -i 's/\r$//' "$file"
    else
        echo "正常: $file"
    fi
done

echo ""
echo "修复完成！"
echo ""
echo "现在可以运行:"
echo "  cd $SCRIPT_DIR"
echo "  ./inspect.sh --help"
