#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%F_%H%M%S)"
OUT="/tmp/day7_drill_${TS}"
mkdir -p "$OUT"

REPORT="$OUT/drill_report.md"
cat > "$REPORT" <<EOF
# Day7 容灾演练记录

- 演练时间：$TS
- 演练负责人：
- 演练范围：备份恢复 / 故障切换

## 时间线
- 故障开始：
- 告警触发：
- 止血完成：
- 恢复完成：

## 指标
- RTO 目标：
- RTO 实测：
- RPO 目标：
- RPO 实测：

## 结果
- 探活检查：通过/失败
- 核心接口：通过/失败
- 数据一致性：通过/失败

## 问题与改进
1. 
2. 
3. 
EOF

echo "[DONE] $REPORT"
