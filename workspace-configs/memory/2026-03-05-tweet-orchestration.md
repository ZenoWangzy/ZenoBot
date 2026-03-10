# 2026-03-05: tweet-orchestration

tags: #session #decision
importance: high
category: decision

- **Session Key**: agent:supervisor:discord:direct:853303202236858379
- **Session ID**: 5388a364-2410-4094-a1b9-402a70456a4f
- **Source**: discord
- **Time**: 05:11:28 UTC

## Decision

assistant: [[reply_to_current]]你这次的目标很明确，我给你一份完整复盘（按你要的四段来）。

## 1) 你的目的

你要的是一件事，不是两件：

**深度研究 Elvis 那条推文的方法论 → 产出一套适配你 OpenClaw 的单一落地方法**，并且执行过程要符合你的习惯：

- 复杂任务默认派给 CC/Codex，不手搓
- 派发后必须有 cron/watcher 每 5 分钟检查
- 任务结束后清理检查任务

---

## 2) 现在是怎么实现的（实际执行路径）

本次实际链路：

1. 你给了推文链接
2. 我按 superpowers skill 派发 CC 任务（`sp-orchestration-tweet-deep`）
3. 创建了 5 分钟 cron 检查（已符合你要求）
4. 中间发生 ECONNRESET，按规则做了 continue/retry
5. 最终报告文件落地：  
   `/Users/ZenoWang/.openclaw/workspace/cc-superpowers-report-orchestration.md`
6. 任务结束后，我已清理进度 cron（`aa2d...` 已 remove）

---

## 3) 出现了什么问题（核心故障）

### 现象层

- 你看到 `Exec completed code 0`，但任务还在跑
- 进程在跑，`task-output.txt` 长时间 0 字节
- `latest.json` 显示 done，但真实任务状态并不一致

### 根因层（重点）

1. **“派发成功”被误读为“任务完成”**  
   `dispatch-claude.sh` 是 `nohup` 异步启动，父进程立刻退出。  
   所以 code 0 只表示“启动了”，不是“做完了”。

2. **状态文件是全局单例，天然会串线**  
   用的是单一：
   - `task-meta.json`
   - `task-output.txt`
   - `task-exit-code.txt`  
     重试/并发时会互相覆盖，状态污染。

3. **完成判定逻辑不严谨**  
   `notify-openclaw-dispatch.sh` 收到 `Stop/SessionEnd` 就可能写 `status: done`，  
   但没强依赖“exit code 已写 + 目标报告已生成”。

4. **“进程存活但无输出”路径没闭环**  
   网络抖动/CLI卡住时，stdout 可能长期无刷新；当前机制对这类“活着但不推进”的处理不够硬。

---

## 4) 要改的话，具体怎么改（可直接开工）

下面是**最小可行改造**，我建议你按这个做，别大改。

---

### A. 先做 run 隔离（最关键）

改 `claude-code-dispatch-macos/scripts/dispatch-claude.sh`

**改法：**

- 每次派发生成 `run_id`（时间戳+task）
- 写到：`data/runs/<run_id>/`
  - `meta.json`
  - `output.txt`
  - `exit-code.txt`
- `data/latest.json` 只当“指针”（current_run_id），不当真相源

**收益：**

- 重试/并发不再互相覆盖
- 每个 run 都可追溯

---

### B. 完成判定改成“双条件”

改 `notify-openclaw-dispatch.sh`

**done 条件必须满足其一：**

1. `exit-code.txt` 存在且有值
2. 目标报告文件存在且非空（本任务是 `cc-superpowers-report-orchestration.md`）

否则只能标 `running/stalled`，不能标 done。

---

### C. watcher 负责“状态收敛”

改 `watch-cc-task.sh`

**新增逻辑：**

- 连续 N 分钟无输出且无报告文件 => 标记 `stalled`
- 若输出命中 `unable to connect|ECONNRESET`：
  - 自动走 continue/retry（最多 3 次）
  - 每次重试写入 run 事件日志
- 最终失败要写 `failed`（不是悬空 running）

---

### D. 通知和状态解耦

现在 hook 做太多。建议：

- hook：只上报事件（Stop/SessionEnd）
- reconcile 脚本：统一读取 run 目录，决定真实状态并写回
- 通知发出后记录 `delivery_success/failure`，不能默默吞掉

---

### E. 你的习惯自动化（已执行，但建议固化到代码）

你要求的规则已经记住并写入 USER.md，但建议代码再加一层硬约束：

- dispatch 成功后自动创建 progress cron/watcher
- 当 active run = 0 时，自动清理相关 cron/watcher

这样不会再靠“我记得”。

---

## 当前状态（给你一句结论）

- 你要的“工具化执行 + 5分钟巡检 + 任务后清理”已经在这次流程跑通
- 但底层 dispatch 状态机仍有结构性缺陷（全局单文件 + 完成判定不一致）
- 不修这层，后面还会反复出现“看似完成/实际卡住”的假象

---

你要的话我下一步直接给你一份**文件级 patch 清单**（每个文件改哪几段、字段怎么定义、状态机转移图），你照着改就行。
user: Conversation info (untrusted metadata):

```json
{
  "timestamp": "Thu 2026-03-05 12:49 GMT+8"
}
```

重构完成 ★ Insight ───────────────────────────────────── 状态机重构核心改进： 1. Per-Run 隔离：每个任务有独立 runs/<run_id>/ 目录，状态文件不污染 2. 指针模式：latest.json 只存 current_run_id，避免并发覆盖 3. Watchdog 状态收敛：进程退出时由 watchdog 写入最终状态，不依赖 Hook 4. 双条件完成判定：exit_code 落盘 或 required_output 存在才判定完成 ───────────────────────────────────────────────── 改动文件 ┌─────────────────────────────┬──────────────────────────────────────────────────────────┐ │ 文件 │ 改动内容 │ ├─────────────────────────────┼──────────────────────────────────────────────────────────┤ │ dispatch-claude.sh │ 添加 RUN_ID 生成、per-run 目录、--required-output 参数 │ ├─────────────────────────────┼──────────────────────────────────────────────────────────┤ │ watch-cc-task.sh │ 添加状态收敛逻辑（write_final_status）、自动重试支持 │ ├─────────────────────────────┼──────────────────────────────────────────────────────────┤ │ notify-openclaw-dispatch.sh │ 添加 is_task_complete() 双条件判定、Hook 不再直接写 done │ └─────────────────────────────┴──────────────────────────────────────────────────────────┘
assistant: [[reply_to_current]]这次重构方向是对的，骨架已经从“脆弱脚本”变成“可维护状态机”了。  
我刚快速过了一遍实现，有两点你最好马上补：

1. **`watch-cc-task.sh` 的自动重试计数是假的**  
   `retry_count` 初始化后没持久化递增，跨进程/跨重试不会累计，容易无限“看起来在重试”。  
   → 建议把 retry 次数写进 `meta.json`（`retry_count`）并由 watchdog 每次读取+1+回写。

2. **`--argjson exit_code` 有类型风险**  
   `exit_code` 来源是文本文件，空值/非数字会让 jq 报错。  
   → 先做数字兜底：`ec_num=$(echo "$ec" | grep -E '^[0-9]+$' >/dev/null && echo "$ec" || echo 1)` 再喂 `--argjson`.

另外一个建议（非阻塞但该做）：

- `required_output` 建议支持相对路径并基于 `workdir` 解析，否则跨目录任务会误判未完成。

总体评价：**80% 到位，核心架构已经正确；把这 2 个坑补了就能稳定上线。**
user: [Queued messages while agent was busy]

---

Queued #1
Conversation info (untrusted metadata):

```json
{
  "timestamp": "Thu 2026-03-05 12:49 GMT+8"
}
```

新增功能 1. Per-Run 目录结构： data/runs/<timestamp>-<task-name>/ ├── meta.json # 任务元数据 + 状态 ├── output.txt # 任务输出 └── exit-code.txt # 退出码 2. latest.json 指针格式： { "current_run_id": "1772682318-my-task", "task_name": "my-task", "status": "running", "started_at": "2026-03-05T11:45:18+08:00" } 3. 双条件完成判定： - 条件1：exit-code.txt 存在且非空 - 条件2：required_output 文件存在且非空 4. 向后兼容：保留全局 task-meta.json 作为兼容层 测试验证 - ✅ 语法检查通过 - ✅ Per-run 目录创建正常 - ✅ 状态写入/更新正常 - ✅ is_task_complete() 双条件判定正常 - ✅ 完整状态机生命周期测试通过

---

Queued #2
Conversation info (untrusted metadata):

```json
{
  "timestamp": "Thu 2026-03-05 12:49 GMT+8"
}
```

你审核一下，这是cc给我的
assistant: [[reply_to_current]]审核结论：**方向正确，80分，可用但还没到“稳态上线”**。  
你这版确实把最关键的结构问题扳正了（per-run + 指针 + watchdog收敛 + 双条件判定），这点非常好。

### ✅ 我确认做对了的点

1. **Per-run 隔离**：`data/runs/<run_id>/meta|output|exit`，解决状态污染。
2. **latest.json 指针化**：不再把它当唯一真相源。
3. **Hook 降权**：不再直接盲写 done。
4. **双条件完成判定**：比之前可靠很多。
5. 语法层面：3个脚本 `bash -n` 都过了。

---

### ⚠️ 还存在的关键问题（建议立即修）

1. **retry 计数没真正生效**（`watch-cc-task.sh`）  
   `retry_count=0` 只在当前进程内，没持久化、没递增写回，等于“看起来有重试机制，实际上不受控”。

2. **retry queue 路径可疑**  
   `queue_file="${run_dir}/../queue/...json"` 实际会落到 `data/runs/queue/`，通常消费端监听的是 `data/queue/`。  
   这会导致“创建了重试文件但没人消费”。

3. **notify 的 fallback 完成判定可能误判 failed**  
   当 `required_output` 已满足但 `EXIT_CODE` 为空时，你现在逻辑会走 `EXIT_CODE != 0 -> failed`。  
   这种场景应该判 `done`（或 `done-without-exit`），不该直接 failed。

4. **required_output 路径解析不健壮**  
   现在是按绝对/当前路径直接查，若给相对路径且 cwd 不一致会误判未完成。  
   应基于 `meta.workdir` 解析相对路径。

---

### 我给你的上线建议

- 先把上面 4 个点补掉，再说“状态机重构完成”。
- 补完后再跑一次实战压测：
  - 正常成功
  - API 断连后自动重试
  - required_output 提前生成
  - 并发两任务互不污染

如果你要，我可以直接给你一份**最小补丁清单（逐文件、逐段修改）**，你让 CC 按清单一次补齐。
assistant: 审核结论：**方向正确，80分，可用但还没到“稳态上线”**。
你这版确实把最关键的结构问题扳正了（per-run + 指针 + watchdog收敛 + 双条件判定），这点非常好。

### ✅ 我确认做对了的点

1. **Per-run 隔离**：`data/runs/<run_id>/meta|output|exit`，解决状态污染。
2. **latest.json 指针化**：不再把它当唯一真相源。
3. **Hook 降权**：不再直接盲写 done。
4. **双条件完成判定**：比之前可靠很多。
5. 语法层面：3个脚本 `bash -n` 都过了。

---

### ⚠️ 还存在的关键问题（建议立即修）

1. **retry 计数没真正生效**（`watch-cc-task.sh`）
   `retry_count=0` 只在当前进程内，没持久化、没递增写回，等于“看起来有重试机制，实际上不受控”。

2. **retry queue 路径可疑**
   `queue_file="${run_dir}/../queue/...json"` 实际会落到 `data/runs/queue/`，通常消费端监听的是 `data/queue/`。
   这会导致“创建了重试文件但没人消费”。

3. **notify 的 fallback 完成判定可能误判 failed**
   当 `required_output` 已满足但 `EXIT_CODE` 为空时，你现在逻辑会走 `EXIT_CODE != 0 -> failed`。
   这种场景应该判 `done`（或 `done-without-exit`），不该直接 failed。

4. **required_output 路径解析不健壮**
   现在是按绝对/当前路径直接查，若给相对路径且 cwd 不一致会误判未完成。
   应基于 `meta.workdir` 解析相对路径。

---

### 我给你的上线建议

- 先把上面 4 个点补掉，再说“状态机重构完成”。
- 补完后再跑一次实战压测：
- 正常成功
- API 断连后自动重试
- required_output 提前生成
- 并发两任务互不污染

如果你要，我可以直接给你一份**最小补丁清单（逐文件、逐段修改）**，你让 CC 按清单一次补齐。
user: Conversation info (untrusted metadata):

```json
{
  "timestamp": "Thu 2026-03-05 12:55 GMT+8"
}
```

cc cli：修复完成 ★ Insight ───────────────────────────────────── 关键修复： 1. retry_count 持久化：从 meta.json 读取 + 递增 + 写回，跨进程正确累计 2. exit_code 类型安全：sanitize_exit_code() 函数兜底空值/非数字 3. retry queue 路径：修正为 ${DATA_DIR}/queue/（消费端监听路径） 4. required_output 相对路径：基于 workdir 解析，跨目录任务不误判 5. required_output 完成判定：满足时标记 done 而非 failed（即使 exit_code 为空） ─────────────────────────────────────────────────
assistant: [[reply_to_current]]这版我刚复审过了：**通过，能上线试跑**。你列的 5 个修复都已落地到代码里了。

我实际检查到的点：

- `watch-cc-task.sh`
  - 有 `sanitize_exit_code()`（空值/非数字兜底）
  - retry_count 从 `meta.json` 读取并递增回写（持久化）
  - retry queue 改到 `data/queue/`，且 worker 确实监听这个目录
- `notify-openclaw-dispatch.sh`
  - `required_output` 相对路径按 `workdir` 解析
  - `required_output` 满足时 fallback 判定为 `done`（不会误判 failed）
- 两个脚本语法检查通过（`bash -n` OK）

唯一提醒：你这批改动目前还是未提交状态（脚本文件有修改）。  
建议立刻 commit 一把，比如：

`fix(dispatch): harden per-run state machine retry/output completion semantics`

总体评价：**这次是真修到了根上。**
user: [Queued messages while agent was busy]

---

Queued #1
Conversation info (untrusted metadata):

```json
{
  "timestamp": "Thu 2026-03-05 12:55 GMT+8"
}
```

修复详情 ┌──────────────────────────────────────┬─────────────────────────────────────────────────────┐ │ 问题 │ 修复方案 │ ├──────────────────────────────────────┼─────────────────────────────────────────────────────┤ │ retry_count 跨进程失效 │ get_retry_count() / increment_retry_count() 从 │ │ │ meta.json 读写 │ ├──────────────────────────────────────┼─────────────────────────────────────────────────────┤ │ exit_code 空值/非数字导致 jq 报错 │ sanitize_exit_code() 函数验证正则 │ │ │ ^[0-9]+$，否则返回 1 │ ├──────────────────────────────────────┼─────────────────────────────────────────────────────┤ │ retry queue 路径错误 │ ${run_dir}/../queue/ → ${DATA_DIR}/queue/ │ ├──────────────────────────────────────┼─────────────────────────────────────────────────────┤ │ required_output 相对路径 │ 检测 != /* 则拼接 ${workdir}/${raw_path} │ ├──────────────────────────────────────┼─────────────────────────────────────────────────────┤ │ required_output 满足但 exit_code │ COMPLETION_REASON="required_output" 时设 │ │ 为空时误判 failed │ TASK_STATUS="done" │ └──────────────────────────────────────┴─────────────────────────────────────────────────────┘ 测试验证 === Test 1: sanitize_exit_code === ✅ Empty -> 1 ✅ Non-numeric -> 1 ✅ Numeric preserved === Test 2: is_task_complete with relative path === ✅ No exit_code, no required_output -> not complete ✅ Relative path resolved: required_output ✅ Exit code takes precedence === Test 3: retry_count persistence === ✅ Initial count: 0 ✅ After increment: 1 ✅ Persisted count: 1

---

Queued #2
Conversation info (untrusted metadata):

```json
{
  "timestamp": "Thu 2026-03-05 12:55 GMT+8"
}
```

文件变更 - watch-cc-task.sh: 添加 sanitize_exit_code(), get_retry_count(), increment_retry_count(), 修正 queue 路径 - notify-openclaw-dispatch.sh: is_task_complete() 支持相对路径解析，COMPLETION_REASON 区分完成条件 状态机重构现已完成，可上线测试。

---

Queued #3
Conversation info (untrusted metadata):

```json
{
  "timestamp": "Thu 2026-03-05 12:56 GMT+8"
}
```

你可以检查一下
assistant: [[reply_to_current]]我检查过了，结论：**这版修复是成立的，可以进上线测试阶段**。

你发的每一项都和代码一致：

- `retry_count` 已持久化到 `meta.json`
- `sanitize_exit_code()` 已补，`jq --argjson` 风险已兜底
- queue 路径已改成 `data/queue/`，且 worker 监听同一路径
- `required_output` 支持相对路径 + `workdir` 解析
- `required_output` 命中时会判 `done`，不再误判 `failed`

下一步别再纸面验证了，直接跑 3 个线上场景：

1. 正常完成
2. API 抖动触发自动重试
3. `required_output` 先于 exit-code 生成

这 3 个过了就可以算“稳定上线”。
assistant: 我检查过了，结论：**这版修复是成立的，可以进上线测试阶段**。

你发的每一项都和代码一致：

- `retry_count` 已持久化到 `meta.json`
- `sanitize_exit_code()` 已补，`jq --argjson` 风险已兜底
- queue 路径已改成 `data/queue/`，且 worker 监听同一路径
- `required_output` 支持相对路径 + `workdir` 解析
- `required_output` 命中时会判 `done`，不再误判 `failed`

下一步别再纸面验证了，直接跑 3 个线上场景：

1. 正常完成
2. API 抖动触发自动重试
3. `required_output` 先于 exit-code 生成

这 3 个过了就可以算“稳定上线”。
user: Conversation info (untrusted metadata):

```json
{
  "timestamp": "Thu 2026-03-05 13:04 GMT+8"
}
```

cc cli：上线测试全部通过 ┌─────────────────────────────────────┬──────┬───────────────────────────────────────────────┐ │ 测试 │ 结果 │ 验证内容 │ ├─────────────────────────────────────┼──────┼───────────────────────────────────────────────┤ │ Test 1: ✅ 正 正任务完成： │ │ │ │ status=done, exit_code=0 │ │ │ ├─────────────────────────────────────┼──────┼───────────────────────────────────────────────┤ │ Test 2 │ ✅ │ relative_path 解 │ │ │ │ /tmp/workdir-98559/build/output.txt │ ├─────────────────────────────────────┼──────┼───────────────────────────────────────────────┤ │ Test 3 │ ✅ │ 并发隔离 │ ├─────────────────────────────────────┼──────┼───────────────────────────────────────────────┤ │ Test 4 │ ✅ │ exit_code 类型安全 │ └─────────────────────────────────────┴──────┴───────────────────────────────────────────────┘ ★ Insight ───────────────────────────────────── 上线测试总结： 1. Per-Run 騡式： 每个任务独立目录，状态不污染 2. 路径解析： 相对路径基于 workdir 正确解析 3. 类型安全： 空值/非数字统一 fallback 到 1 ───────────────────────────────────────── 最终状态 data/runs/<run_id>/ ├── meta.json # 任务元数据（含 status, exit_code, retry_count） ├── output.txt # 任务输出 ├── exit-code.txt # 退出码 data/latest.json # 指针文件（只存 current_run_id + status） 状态机重构完成，已通过全部上线测试。 你自己测试一下呢
assistant: [[reply_to_current]]我刚自己跑了实测，不是口头确认，结果是：**全通过**。

我执行了 4 个自测场景：

1. watchdog 正常收敛：`status=done + exit_code=0` ✅
2. retry 持久化 + 正确写入 `data/queue/` ✅
3. `exit_code` 非数字兜底为 `1`（类型安全）✅
4. `required_output` 相对路径（基于 workdir）可判定完成，且标记 `done` ✅

最终输出：`ALL_SELF_TESTS_PASSED`。  
我也把自测生成的临时 run/queue 文件清理掉了。
user: System: [2026-03-05 13:06:43 GMT+8] Exec completed (swift-gl, code 0) :: PASS: watchdog done+exit0 PASS: retry_count persisted + queue in data/queue PASS: sanitize exit_code non-numeric PASS: required_output relative path completion ALL_SELF_TESTS_PASS…

Conversation info (untrusted metadata):

```json
{
  "timestamp": "Thu 2026-03-05 13:09 GMT+8"
}
```

那提交GitHub保存一下
assistant: [[reply_to_current]]已提交并推到 GitHub 了。

- Commit: `e38b991`
- Message: `fix(dispatch): harden retry persistence and completion checks`
- Branch: `main`
- Remote: `ZenoWangzy/zenomacbot-backup`
- Push: 成功 ✅
