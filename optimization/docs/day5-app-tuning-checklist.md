# Day 5 应用层调优检查清单

## 1. 服务运行参数采样
```bash
ps -ef | egrep 'java|gunicorn|uvicorn' | grep -v grep
```

## 2. Java 进程检查（如有）
```bash
PID=$(pgrep -f 'java' | head -n1)
[ -n "$PID" ] && jcmd "$PID" VM.flags
[ -n "$PID" ] && jstat -gcutil "$PID" 1s 10
```

## 3. Python 服务检查（如有）
```bash
ps -eo pid,ppid,%cpu,%mem,cmd | egrep 'gunicorn|uvicorn' | grep -v grep
ss -s
```

## 4. 线程池/连接池水位（应用指标）
- 线程池 active/max、queue depth
- DB 连接池 active/max/wait
- HTTP client 连接池耗尽次数

## 5. 超时与重试检查
- connect/read/write timeout 是否分离
- 重试次数是否有上限
- 是否有退避与抖动（jitter）
- 非幂等接口是否禁重试

## 6. 灰度观察项（30~60 分钟）
- P95/P99
- 错误率
- 超时率
- 下游依赖成功率

## 7. 回滚触发条件
- P95 恶化 >20% 持续 10 分钟
- 错误率翻倍
- 下游告警明显上升

## 8. 输出模板
- 服务名：
- 本次参数：
- 前后对比：
- 是否回滚：
