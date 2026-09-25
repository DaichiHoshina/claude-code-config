# Claude Code Performance Insights

Measurement-based (initial 2026-04-22, re-measured 2026-05-18). Hook/agent cost structure, measurement pitfalls, re-measurement commands.

## Hook Measurement Pitfalls

**First run is 5-7× slower due to cold cache.**

| hook | First run (misleading) | Warm 5-sample avg |
|------|-----------------------|------------------|
| subagent-start.sh | 520ms | **98ms** |
| session-start.sh | 660ms | **90ms** |
| pre-tool-use.sh | — | 30ms |
| post-tool-use.sh | — | 52ms |
| user-prompt-submit.sh | — | 50ms |
| subagent-stop.sh | — | 100ms |

**Lesson**: Always measure with warmup + 5+ sample average. Judging from first-run values only is misleading.

**Multiple hooks on the same event run in parallel (confirmed 2026-08-22).** Official docs "All matching hooks run in parallel." + measured overlap on 3 timestamp hooks. Timeout is per-hook.

- Estimate event effective latency as "parallel max (+ spawn stagger)". Summing each hook overshoots by multiple factors (real case: summing 3 PreToolUse hooks gave 277ms → actual effective was max ≈ 93ms)
- Proposals to "merge hooks for speedup" are rejected by default: wall-clock effect is near zero. Only the heaviest hook that decides the max is worth trimming
- Verify existing optimizations against the actual code before proposing perf improvements: pre-push hook-bench runs only on hooks/lib changes (conditional branch implemented), memory-dangling-check is `"async": true` and non-blocking
- Median of git-invoking hooks varies by measurement cwd. Real case (2026-08-23): `post-compact-reload.sh` is 129ms in a large repo, 97ms in `~/.claude`; the actual difference is `git status --short` 73ms vs 44ms. `--diff` compares only logs from the same cwd (skips if only different-cwd logs exist)
- Serena `find_symbol` in a large Go repo takes about 2s when scoped to a file, about 8.6s across the whole repo (measured 2026-08-23, after subtracting the ~3.4s tool round-trip). Grepping the same symbol takes 0.21s repo-wide / 0.009s single-file, so **once the target is pinpointed, grep is orders of magnitude faster**. Serena wins when symbol structure or reference relations are needed; do not call it with repo-wide scope for a single known location

## Hook New Baseline (measured 2026-05-18)

`hook-bench.sh` (warmup=5, runs=15). bash spawn baseline = 33ms.

| hook | median | p95 | vs 2026-04-22 |
|------|--------|-----|--------------|
| pre-tool-use.sh | 64ms | 89ms | +34ms |
| setup.sh | 63ms | 81ms | — |
| permission-denied.sh | 72ms | 84ms | — |
| teammate-idle.sh | 79ms | 106ms | — |
| post-tool-use.sh | 84ms | 101ms | +32ms |
| user-prompt-submit.sh | 98ms | 136ms | +48ms |
| post-tool-use-failure.sh | 98ms | 131ms | — |
| task-completed.sh | 106ms | 122ms | — |
| subagent-start.sh | 112ms | 145ms | +14ms |
| session-end.sh | 117ms | 134ms | — |
| subagent-stop.sh | 120ms | 155ms | +20ms |
| session-start.sh | 125ms | 157ms | +35ms |
| post-compact-reload.sh | 127ms | 181ms | — |

**+30–50ms heavier vs 04-22**, but absolute values are all p95 < 200ms. Does not reach perceptible lag threshold (>300ms). **True cost source is agent LLM time** — unchanged. Regression threshold: p95 > 300ms.

Perceived lightness improvement (user report 2026-05-18) is estimated to be driven by **`name-only` skill definition (settings.json 16 entries) + MCP deferred initialization** reducing initial token consumption, not the hook layer.

## Cost Structure (hook vs agent) (small sample, reference values)

ms-level vs minute-level — orders of magnitude apart.

| Layer | Actual time | Notes |
|-------|-------------|-------|
| All hooks (warm) | 30–100ms | N≥15, high confidence |
| developer-agent | **median 101s** (n=31, p25=58s p75=137s) | n=31, high confidence |
| manager-agent | ~42s | n=2, reference only |
| reviewer-agent | ~82s | n=27 |
| po-agent | ~96s | n=9, reference only |
| Explore (built-in) | ~99s | n=79 |
| **general-purpose** | **115s (max 501s)** | n=21 |
| explore-agent | ~123s | n=7, reference only |

> **Note**: developer-agent updated to 2026-05-23 actual measurement n=31 median=101s / avg=113s. Old value (n=4 avg=60s) is a past reference. **n<10 values require re-measurement.**

**True cost source is agent LLM time.** Hook optimization (shaving <100ms) has poor ROI. Improve by reducing agent launch frequency.

## Agent Measurements and Sample Confidence (small sample, reference values)

subagent-events.log aggregation (2026-04-06–2026-04-22) + 2026-05-23 additional measurements.

| agent | N | avg | max | Notes |
|-------|---|-----|-----|-------|
| Explore (built-in) | 79 | 99s | 310s | Highest usage frequency |
| reviewer-agent | 27 | 82s | 161s | Opus + comprehensive-review |
| general-purpose | 21 | **115s** | **501s** | **Avoid** |
| po-agent | 9* | 96s | 365s | Strategic decision-making |
| explore-agent | 7* | 123s | 289s | Haiku but broad task scope |
| manager-agent | 2* | 42s | 68s | Planning only, lightweight |
| developer-agent (haiku) | 17 | 291s | 739s | haiku avg, 2026-04 measurement |
| developer-agent (sonnet) | **31** | **113s** | **451s** | **2026-05-23 actual, median 101s / p25 58s / p75 137s** |

`*` = N<10 (or n<10 equivalent) reference values (small sample, values may change with more data). Prefer N≥20 for operational decisions.

## Operational Rules (abuse prevention)

- 1-2 query investigations: **use Bash grep/find/mcp__serena__find_symbol directly, no agent launch**
- 3+ query broad exploration only: `Task(explore-agent)` ×4 parallel launch
- Claude Code CLI/SDK/API spec questions: `claude-code-guide` agent
- `general-purpose`: hard-blocked by `hooks/pre-tool-use.sh` (exit 2) — N=21 measured, highest cost source. Substitute with explore-agent / claude-code-guide / developer-agent. Escape hatch: `GP_BLOCK_OFF=1` reverts to warn-only (hook debug)

Details: `claude-code/CLAUDE.global.md` "Discovery / Investigation Routing".

## Re-measurement Commands

### Agent actual time aggregation (all periods)

```bash
awk '
  /START/ { for(i=1;i<=NF;i++){if($i~/^agent_id=/){sub("agent_id=","",$i);id=$i};if($i~/^type=/){sub("type=","",$i);t=$i}}; gsub("\\[|\\]","",$1); cmd="date -j -f %Y-%m-%dT%H:%M:%SZ " $1 " +%s 2>/dev/null"; cmd|getline e; close(cmd); s[id]=e; ty[id]=t }
  /STOP/  { for(i=1;i<=NF;i++){if($i~/^agent_id=/){sub("agent_id=","",$i);id=$i}}; gsub("\\[|\\]","",$1); cmd="date -j -f %Y-%m-%dT%H:%M:%SZ " $1 " +%s 2>/dev/null"; cmd|getline e; close(cmd); if(id in s){d=e-s[id]; sum[ty[id]]+=d; cnt[ty[id]]++; if(d>max[ty[id]])max[ty[id]]=d} }
  END { for(t in cnt) printf "%-22s N=%d avg=%.1fs max=%ds\n", t, cnt[t], sum[t]/cnt[t], max[t] }
' ~/.claude/logs/subagent-events.log | sort -k3 -t= -rn
```

### Hook warm measurement (5-sample average)

```bash
INPUT='{"session_id":"test","cwd":"/tmp","agent_id":"a","agent_type":"t"}'
for h in subagent-start.sh session-start.sh pre-tool-use.sh post-tool-use.sh; do
  times=""
  for i in 1 2 3 4 5; do
    t=$({ /usr/bin/time -p bash -c "echo '$INPUT' | ~/.claude/hooks/$h >/dev/null 2>&1"; } 2>&1 | awk '/real/ {print $2}')
    times="$times $t"
  done
  avg=$(echo "$times" | awk '{for(i=1;i<=NF;i++)s+=$i; print s/NF}')
  printf "%-28s avg=%.3fs\n" "$h" "$avg"
done
```

### Team chain measurement (specific time range)

```bash
awk '/^\[2026-04-22T01:3[4-8]/' ~/.claude/logs/subagent-events.log
```

## Sonnet Delegation Overhead Measurement (2026-05-23 N=31 update)

`~/.claude/logs/subagent-events.log` actual (developer-agent sonnet launches N=31, 2026-05-23 same-day).

- Duration distribution: min=22s / p25=58s / median=101s / p75=137s / max=451s / avg=113s
- Lightweight task proxy (bottom 20%): 22, 27, 27, 39, 44, 56 seconds
- Delegate launch floor = 22s (startup overhead: Serena `activate_project` + prompt load). Tasks completing in <20s are clearly better inline
- vs haiku N=17 avg 291s: Sonnet switch **2.6× faster** (hypothesis that Sonnet is slower is rejected)
- Old value "avg 60s / max 91s" was n=2 outlier-based. N=31 shows significant upward revision. **n<10 values require re-measurement**
- Decision threshold: CLAUDE.md "Inline exceptions" threshold of "expected LLM execution <20s (1 symbol / 1 section fix)" is below delegate min (22s) — valid. 20-60s grey zone: maintain "when in doubt, delegate" principle. >60s: delegate is clearly better

## session-init-timing Log Measurement Infrastructure (since fbce383)

Infrastructure for continuous session startup time measurement. Used to accumulate 7–14 days of data to compare baseline against plugin count changes / Serena `~/.claude/projects/` count changes.

**Log / DB**:
- log: `~/.claude/logs/session-init-timing.log` (format: `[timestamp] session_id=X duration_ms=Y plugin_count=Z`, 1000-line circular)
- DB: `~/.claude/logs/analytics.db` `sessions` table, `init_duration_ms INTEGER DEFAULT 0` column

**Measurement hooks**:
- `claude-code/hooks/session-start.sh` L9 records `_SS_START_EPOCH=$(date +%s%N)`, L126 calculates elapsed ms and appends to log
- `claude-code/hooks/session-end.sh` greps duration from timing log and passes as 11th argument to `analytics_insert_session`

**Aggregation command**:

```bash
sqlite3 ~/.claude/logs/analytics.db 'SELECT AVG(init_duration_ms) FROM sessions GROUP BY DATE(start_ts)'
```

## Context Management measurement metadata (measured 2026-06-19)

Delegation target for measured values in CLAUDE.md `## Context Management`.

### Measured cost

- **150-300 msg session**: cache_read range of $30-$45 / session
- cache_read is **charged per turn at base-context size** (proportional to turn count)
- cache_read accumulation over long sessions is the single largest cost driver per session

### `user-prompt-submit.sh` auto-warn thresholds

- **warn**: first warn at 150 msg (~75 turn)
- **urgent**: urgent warn at 350 msg (~175 turn)
- Action on warn: finish current task to a break point → `/clear` for context reset
- `/clear` timing: immediately after task completion (clearing mid-task causes context loss)

### `/clear` vs `/compact` decision

| Situation | Recommendation |
|---|---|
| context over 40%, task ongoing | `/compact` (summarize, inherit context) |
| context over 40%, task at break point | `/clear` (full reset, fresh cache) |
| idle for 5+ min (cache TTL expired) | `/clear` (cache is stale, inheritance unnecessary) |
| same problem failed twice in a row | `/clear` + rewrite prompt (accumulated failure context is the main cause, not capacity shortage) |

### Continue pattern

- Interrupted task inheritance: in chat, "generate next-session mega-prompt" → paste output to new session
- Untainted one-off question: `/btw` (ask a different question while keeping current context)

### Token audit before reduction

session の token 消費が多いと感じたときは、行数ベースの推測より `/context` の出力を先に取る。CLAUDE.md 階層 / rule / skill / command description / MCP tool schema / plugin ごとの token 内訳が category 別に表示されるので、どの category が実際に大きいかを実測ベースで判定できる。

2026-09-15 の実測では、「CLAUDE.md 階層 import 332 行」「rules 232 行」を主な削減対象と推測していたが、実際に効いていたのは MCP tool schema (Notion 44 + Slack 18 + Google Calendar 9 = 71 個の deferred tool schema) で、手動 disconnect した後に一気に軽くなった。行数ベースの推測は order of magnitude を読み誤る。

**削減しやすい category と方法**:

| category | 削減手段 |
|---|---|
| MCP tool schema | Claude.ai integrations 設定で不要 MCP を disconnect (Notion / Slack / Google Calendar 等) |
| `.claude.json` の mcpServers | 未使用 MCP を削除 |
| enabledPlugins | `settings.json` で `false` に変える (LSP / warp 等の未使用 plugin) |
| rules (無条件 auto-load) | 詳細 pitfall を `references/on-demand-rules/` へ移す |
| CLAUDE.md 階層 | 階層 import の再配置 (effect 小、優先度低) |

**削減不能** (harness 側で制御): system-reminder 群 (agent 一覧 / skill 一覧 / MCP instructions / deferred tool 列挙) / Claude.ai 側で attach された integrations の tool 一覧。

修正後は新 session (`/clear` 後) で再度 `/context` を実行して before/after を比較する。

## TTFT measurement — response wait breakdown (measured 2026-08-22)

Compared time-to-first-token across conditions using `claude -p` (sonnet, stream-json).

| Condition | first_token |
|---|---|
| Minimal context, no MCP | ~2.5s (per-response fixed cost = API round trip) |
| ai-tools dir, MCP enabled | ~4.0s |
| +200KB context (cache miss) | ~6.4s |
| +200KB context (cache hit) | ~3.9s |

- **Response wait is dominated by context size × cache state**. +200KB context adds +3.9s cold / +1.4s warm. The first prompt after idle is heavy because of the cold portion after cache TTL expiry
- UserPromptSubmit hook (~130ms) is within noise; blaming the hook layer is off-target
- MCP (serena + context7) startup of ~1.5s happens once per session. In dirs not indexed by serena, init takes ~4s (presumed project scan)
- Countermeasure priority: (1) keep sessions short (see the `/clear` / `/compact` table above) (2) delegate tool-call-heavy work to keep parent context light (3) continue compressing auto-loaded docs (estimated warm ~0.3s/msg) (4) use sonnet / fast mode when speed matters

## Large-repo git status latency (measured 2026-08-22)

In repos with tens of thousands of tracked files, `git status` consistently takes ~0.4s (full untracked scan), making statusline periodic refresh and status-invoking hooks (post-compact-reload etc.) permanently heavy. Per-turn hooks do not regress, so when it "feels heavy in some repos" suspect status call sites first.

- Measured: 0.41s status in a 29,000-file repo → 0.04s with `git config core.untrackedcache true` + `git config core.fsmonitor true`. Hook side also dropped 510ms → 130ms
- Local config only, repo-managed files unchanged, shared with worktrees. fsmonitor daemon auto-starts on the first status (+0.5s) and stays resident
- Apply the same 2 settings when cloning a new large repo. To revert, use two `git config --unset`

## jp-quality NG check cost per write (measured 2026-09-21)

`_block_if_ai_jargon` runs on every Write / Edit of a `.md` / `.txt` file (via `hooks/lib/write-checkers.sh` `_run_ai_jargon_check`) and on commit / PR / MCP text. It costs 115ms per call with the shipped setting, which is not visible in `hook-bench`.

| Condition | Per call |
|---|---|
| `JP_QUALITY_STYLE_ENFORCEMENT=1` (settings.json default) | 115ms |
| Same, text hits an NG term | 285ms |
| `JP_QUALITY_STYLE_ENFORCEMENT` unset | 27ms |

- `sys` exceeds `user`, so the cost is subprocess spawning, not computation
- The enforce branch accounts for 88ms of the 115ms. Only 17ms of that is identified: `_assert_required_keys` 7.5ms + 14× `_extract_term_list` 3ms + `_append_jp_quality_inject_log` 6.5ms. **The remaining 71ms is unexplained** and sits in enforce-gated work later in the function
- `hook-bench.sh` reports `pre-tool-use.sh` at 55ms median because its synthetic input never reaches this path. Measure this function directly, not through the bench
- This is also why the heaviest bats files are heavy: `lib/jp-quality-check-block.bats` is 94.5s for 51 tests, and `tests/helpers/jp-quality-check.bash` fixture generation is only 3ms of that

Re-measure:

```bash
T=$(mktemp -d); mkdir -p "$T/.claude/guidelines/writing"
cp guidelines/writing/NG-DICTIONARY.md "$T/.claude/guidelines/writing/"
/usr/bin/time -p bash -c "export HOME='$T'; source '$PWD/lib/jp-quality-check.sh'
  for i in \$(seq 20); do GUARD_CLASS=''; MESSAGE=''; ADDITIONAL_CONTEXT=''; TOOL_NAME=''
    _block_if_ai_jargon 'この関数は入力を検証してから保存する。' 'commit message' >/dev/null 2>&1; done"
rm -rf "$T"
```

Investigation stopped here by user decision (2026-09-21): the absolute saving is small (115ms × writes per day), and the function is the core of a block hook. Resume from the unexplained 71ms if write latency becomes a concern.

## Cost aggregation tool suite

| script | Purpose | Invocation |
|---|---|---|
| `scripts/usage-stats.sh` | Detect zero-usage slash commands / skills (also invoked via `health-check.sh`) | `./scripts/usage-stats.sh --days 30` |
| `scripts/session-cost-top.sh` | Per-session cost top-N + msg count + agent launch count (ccusage + jsonl join) | `./scripts/session-cost-top.sh --top 10 --since 2026-06-25` |
| `scripts/analytics-report.py` | Tool / agent usage aggregation from analytics.db | `./scripts/analytics-report.py --days 7` |
| `scripts/health-check.sh` | Session health report bundling the 3 above + hook-bench | `./scripts/health-check.sh` |
