---
name: security-scan
description: "Scan code for security vulnerabilities before committing. Checks for hardcoded secrets, input validation, auth bypass, OWASP Top 10 patterns. Invoke this after implementing and before committing."
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash, Read, Grep, Glob
---

# Security Scan

Check for common security vulnerabilities before committing code. This skill MUST run the actual grep/scan commands below.

---

## Step 1: Check for Secrets

Run ALL of these commands:

```bash
grep -rn "password\s*=" . --include="*.py" --include="*.js" --include="*.ts" | grep -v node_modules | grep -v ".venv"
grep -rn "api_key\s*=" . --include="*.py" --include="*.js" --include="*.ts" | grep -v node_modules
grep -rn "secret\s*=" . --include="*.py" --include="*.js" --include="*.ts" | grep -v node_modules
grep -rn "token\s*=" . --include="*.py" --include="*.js" --include="*.ts" | grep -v node_modules
grep -rn "Bearer \|Basic " . --include="*.py" --include="*.js" | grep -v node_modules
```

Check .env is gitignored:
```bash
cat .gitignore 2>/dev/null | grep -q ".env" && echo "PASS: .env in .gitignore" || echo "WARNING: .env not in .gitignore"
```

## Step 2: Injection Patterns

```bash
grep -rn "execute\|\.raw\|system\|exec(\|eval(" . --include="*.py" --include="*.js" --include="*.ts" | grep -v node_modules | grep -v ".venv"
grep -rn "innerHTML\|dangerouslySetInnerHTML\|v-html" . --include="*.js" --include="*.tsx" --include="*.vue" | grep -v node_modules
```

## Step 3: Insecure Deserialization

```bash
grep -rn "pickle\|yaml\.load\|eval(" . --include="*.py" | grep -v ".venv"
```

## Step 4: Known Vulnerabilities (if applicable)

```bash
# Node.js
[ -f package.json ] && npm audit --audit-level=high 2>/dev/null || true
```

---

## Output Format

```
## Security Scan Results

### Secrets Check
- [x/✗] No hardcoded passwords
- [x/✗] No API keys in code
- [x/✗] .env properly gitignored

### Injection Patterns
- [x/✗] No eval/exec usage
- [x/✗] No innerHTML usage
- [x/✗] No raw SQL

### Findings
[List any issues with severity CRITICAL/WARNING and file:line location]

### Status: PASS / FAIL
```
