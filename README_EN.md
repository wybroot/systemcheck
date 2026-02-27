# systemcheck: Ops Inspection & Optimization Toolkit

`systemcheck` is a practical repository for **inspection, diagnosis, and optimization** in Linux operations workflows.

## What is included

- `sys_inspection/`: server inspection system (Shell + Web + schedule + alerts)
- `java_diagnosis/`: Java high-CPU troubleshooting script
- `optimization/`: Day1~Day7 production optimization SOP and scripts

## Quick start

### 1) Server inspection

```bash
cd sys_inspection
bash inspect.sh --help
```

### 2) Java high-CPU diagnosis

```bash
cd java_diagnosis
bash java_cpu_diagnosis.sh -h
```

### 3) Production optimization workflow

```bash
cd optimization/scripts
bash day1_audit.sh
```

## Key docs

- `sys_inspection/README.md`
- `java_diagnosis/README.md`
- `optimization/docs/production-server-optimization-sop.md`

For full Chinese documentation and architecture overview, see the root `README.md`.
