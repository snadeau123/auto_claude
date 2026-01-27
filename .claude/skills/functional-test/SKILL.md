---
name: functional-test
description: "Test the running application using Playwright headless browser or Chrome MCP. Takes screenshots, clicks elements, reads console errors, verifies UI renders correctly. Invoke this after implementing a feature."
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash, Read, Write, mcp__claude-in-chrome__tabs_context_mcp, mcp__claude-in-chrome__tabs_create_mcp, mcp__claude-in-chrome__navigate, mcp__claude-in-chrome__computer, mcp__claude-in-chrome__find, mcp__claude-in-chrome__read_page, mcp__claude-in-chrome__form_input, mcp__claude-in-chrome__get_page_text, mcp__claude-in-chrome__read_console_messages, mcp__claude-in-chrome__javascript_tool
---

# Functional Test

Test the application using **Playwright headless browser** (primary) or **Chrome MCP** (when available outside sandbox).

---

## Step 1: Launch a Local Server

Pick a port in the **8500–8550** range and start a server:

```bash
# Static HTML/JS project
python3 -m http.server 8500 &
sleep 2

# Node project
PORT=8500 npm run dev &
sleep 3
```

Verify it is up:
```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:8500
```

If the port is taken, increment (8501, 8502, ...) up to 8550.

---

## Step 2: Choose Test Method

Try **Playwright first** (works inside sandbox). Fall back to **Chrome MCP** only if Playwright is unavailable AND Chrome MCP tools are accessible.

### Option A: Playwright (preferred)

Write a test script to `/tmp/playwright-test-<name>.js` and run it through the runner:

```bash
node .claude/skills/playwright-test/run.js /tmp/playwright-test-<name>.js
```

**IMPORTANT**: Always use `run.js` to execute tests — NEVER run scripts directly with `node /tmp/...`.
The runner handles Playwright module resolution and auto-installation.

Example test script:

```javascript
const browser = await require('playwright').chromium.launch({
  headless: true,
  args: ['--no-sandbox', '--disable-setuid-sandbox']
});
const context = await browser.newContext({ viewport: { width: 1280, height: 720 } });
const page = await context.newPage();

// Navigate
await page.goto('http://localhost:8500');
await page.waitForLoadState('networkidle');

// Screenshot
await page.screenshot({ path: '/tmp/test-screenshot.png', fullPage: true });
console.log('Screenshot saved to /tmp/test-screenshot.png');

// Check for console errors
const errors = [];
page.on('console', msg => { if (msg.type() === 'error') errors.push(msg.text()); });
await page.reload();
await page.waitForLoadState('networkidle');

// Check page content
const title = await page.title();
console.log('Page title:', title);

const bodyText = await page.textContent('body');
console.log('Page has content:', bodyText.length > 0);

// Report errors
if (errors.length > 0) {
  console.log('Console errors found:', errors);
} else {
  console.log('No console errors');
}

await browser.close();
```

The helpers in `.claude/skills/playwright-test/lib/helpers.js` provide utilities:
- `helpers.launchBrowser()` — launch with sane defaults
- `helpers.createContext(browser, options)` — context with viewport, headers
- `helpers.waitForPageReady(page)` — smart wait for networkidle
- `helpers.safeClick(page, selector)` — click with retry logic
- `helpers.takeScreenshot(page, name)` — timestamped screenshot
- `helpers.detectDevServers()` — scan common ports for running servers

To use helpers from your test script:
```javascript
const helpers = require('.claude/skills/playwright-test/lib/helpers');
// OR if running via run.js, helpers is auto-available
```

### Option B: Chrome MCP (fallback — outside sandbox only)

If Playwright is not installed and Chrome MCP tools are available:
1. `mcp__claude-in-chrome__tabs_context_mcp` with `createIfEmpty=true`
2. `mcp__claude-in-chrome__tabs_create_mcp` for a fresh tab
3. `mcp__claude-in-chrome__navigate` to the localhost URL
4. `mcp__claude-in-chrome__computer` with `action="screenshot"`
5. `mcp__claude-in-chrome__read_console_messages` with `onlyErrors=true`

### Option C: CLI-only (last resort)

If neither Playwright nor Chrome MCP is available:
```bash
curl -s http://localhost:8500 | head -50
curl -s -o /dev/null -w "%{http_code}" http://localhost:8500
```

---

## Test Scenarios

### For Web Games (Three.js, Canvas)
1. Navigate, wait for load
2. Screenshot — verify canvas is not blank
3. Check console for WebGL/JS errors
4. Click to interact (e.g. pointer lock, buttons)
5. Screenshot after interaction

### For Forms
1. Navigate to form page
2. Fill fields with `page.fill(selector, value)`
3. Submit with `page.click('button[type=submit]')`
4. Verify success message or redirect

### For APIs (non-UI)
```bash
curl -s http://localhost:8500/api/endpoint | head -20
```

---

## Error Handling — CRITICAL

**You MUST NOT stop when a test tool fails.** Instead:

1. If Playwright crashes: check server is running, retry once, then fall back to Chrome MCP or CLI.
2. If Chrome MCP fails: fall back to CLI checks.
3. After 3 retries on the same step, move on and report the failure.
4. **Never let a test error halt the entire workflow.** Always report results and continue.

---

## Output Format

```
## Functional Test Results

**URL**: http://localhost:XXXX
**Method**: Playwright / Chrome MCP / CLI
**Screenshots**: N taken (paths listed)

### Checks
- [x/✗] Page loads without errors
- [x/✗] Main UI elements visible
- [x/✗] No console errors
- [x/✗] Core functionality works

### Console Errors
None / [list errors found]

### Status: PASS / FAIL
[If FAIL, list issues found]
```
