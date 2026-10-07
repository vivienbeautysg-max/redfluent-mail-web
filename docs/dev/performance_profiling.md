## Performance Profiling

### Why Chrome DevTools instead of Flutter DevTools?

Flutter DevTools is designed for native (iOS/Android/Desktop) profiling and provides frame-level insights via the Dart VM. On **Flutter Web**, Dart code is compiled to JavaScript and rendered via **CanvasKit** (WebAssembly + WebGL). Flutter DevTools cannot profile the JavaScript execution, browser rendering pipeline, or WebGL compositing that CanvasKit relies on.

**Chrome DevTools Performance panel** is the right tool for Flutter Web because it captures the actual browser behavior: main thread long tasks during JMAP response parsing, animation frame budgets on the inbox email list, garbage collection pauses, OIDC/JMAP network timing, and GPU compositing — which is where the real bottlenecks are on web.

### Why automate profiling?

Profiling Flutter Web manually with Chrome DevTools requires repeating the same steps each time: open DevTools, start a trace, navigate through the app, stop the trace, then visually inspect the flame chart for long tasks, jank, and network issues. This process is time-consuming, hard to reproduce consistently, and difficult to compare across branches. By automating the workflow with Chrome DevTools MCP, every run follows the same sequence, collects the same metrics, and outputs a structured report — making it easy to compare performance before and after a change.

### Automated profiling with Chrome DevTools MCP

We use the [Chrome DevTools MCP](https://github.com/ChromeDevTools/chrome-devtools-mcp/?tab=readme-ov-file) server connected to Claude Code to **automate the entire profiling workflow**:

1. **Install the MCP server** — add to your Claude Code MCP configuration (`~/.claude.json` or project `.claude/settings.local.json`):

   ```json
   {
     "mcpServers": {
       "chrome-devtools": {
         "command": "npx",
         "args": ["-y", "chrome-devtools-mcp@latest"]
       }
     }
   }
   ```

2. **Configure `env.file`** for your dev environment (set `SERVER_URL`, `DOMAIN_REDIRECT_URL`, OIDC client, etc.) before running.

3. **Start the app in profile mode**:

   ```bash
   flutter run -d web-server --web-port=2023 --profile
   ```

4. **Run the performance trace** in Claude Code:

   ```text
   /perf-trace-flutter-web 2023
   ```

5. **Follow the prompts** — log in to Twake Mail via OIDC in Chrome, then interact with the app (open emails, navigate folders, compose, search) when asked.

Periodically, manually scroll through the app using your mouse to make sure that the programmatic scrolling isn't skewing the data.

6. **What the AI does automatically**:
    - Connects to the running Chrome instance via the DevTools Protocol
    - Sets CPU 4× throttling to simulate a low-end device
    - Starts a performance trace recording and reloads the page (OIDC tokens in IndexedDB survive reloads)
    - Collects cold-start metrics (TTFB, FCP, DOM Complete, first JMAP request timing)
    - Measures animation frame durations on idle inbox and during scroll
    - Monitors FPS, long tasks, and network activity during interactive user session
    - Takes heap snapshots and checks for memory leaks across GC cycles
    - Analyzes all network requests (JMAP calls, WebSocket frames, cache hits, failures)
    - Runs a Lighthouse audit for PWA and accessibility checks
    - Saves raw trace JSON, markdown report, and per-phase screenshots

7. **For before/after comparison**: switch to the baseline branch first, run the trace, then switch to your feature branch and run again. Compare the two markdown reports side by side.

### Key metrics to watch

| Metric | Target | Description |
|--------|--------|-------------|
| TTFB | < 200ms | Time to first byte from the server |
| FCP | < 1800ms | First Contentful Paint — when the user first sees content |
| First JMAP request | < 1000ms | Time for the first JMAP email fetch to complete |
| Animation frame avg | < 16.7ms | Average frame duration (60fps = 16.7ms budget) |
| Jank (frames > 33.3ms) | < 2% | Percentage of frames exceeding 2× frame budget (dropped frames) |
| Long tasks (> 50ms) | Minimize | Tasks that block the main thread and cause visible stuttering |
| JS Heap growth | < 10MB | Memory growth across GC cycles — high values indicate leaks |
| Cache hit rate | > 50% | Ratio of cached responses — low values increase load time |
| Failed requests | 0 | HTTP errors (status >= 400) during the session |

### Output

Results are saved to `.claude/perf-output/`:

```text
.claude/perf-output/
├── logs/
│   ├── perf-report-{timestamp}.md      # Human-readable markdown report
│   ├── perf-trace-{timestamp}.json.gz  # Raw Chrome trace data
│   ├── perf-latest.json                # Latest run (JSON)
│   └── heap-{timestamp}.heapsnapshot   # Heap snapshot (optional)
└── screenshots/                        # Per-phase screenshots
```

The markdown report includes status indicators: 🟢 Good, 🟡 Warning, 🔴 Poor — with benchmarks for each metric.
