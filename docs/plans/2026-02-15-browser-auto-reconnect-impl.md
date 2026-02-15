# 浏览器自动重连功能实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 实现浏览器自动化连接的全自动启动、守护和恢复，达到零手动干预的目标。

**Architecture:** 采用 CDP 直连优先 + 扩展中继降级的双模式架构，通过守护进程监控连接状态，断开时自动重连或重启浏览器。

**Tech Stack:** TypeScript, Playwright, Chrome DevTools Protocol, Node.js child_process

---

## 执行顺序总结

| Task | 描述 | 依赖 |
|------|------|------|
| 1 | 扩展 BrowserConfig 类型 | 无 |
| 2 | 创建 BrowserLauncher | Task 1 |
| 3 | 创建 ConnectionWatchdog | Task 2 |
| 4 | 创建 SessionStateRecovery | 无 |
| 5 | 改造 pw-session.ts | Task 2, 3, 4 |
| 6 | 优化 extension-relay.ts | 无 |
| 7 | 集成到 server-context.ts | Task 5, 6 |
| 8 | 集成测试 | Task 7 |

**预计总提交数：8 个**

---

## Task 1: 扩展 BrowserConfig 类型

**Files:**
- Modify: src/config/types.browser.ts
- Test: src/config/types.browser.test.ts (新建)

添加 BrowserConnectionMode, BrowserCdpConfig, BrowserWatchdogConfig, BrowserTimeoutConfig 类型。

---

## Task 2: 创建 BrowserLauncher

**Files:**
- Create: src/browser/launcher.ts
- Test: src/browser/launcher.test.ts

实现 detectExistingCDP, findChromeExecutable, launchWithCDP 函数。

---

## Task 3: 创建 ConnectionWatchdog

**Files:**
- Create: src/browser/watchdog.ts
- Test: src/browser/watchdog.test.ts

实现守护进程类，监控连接状态，自动重连和重启。

---

## Task 4: 创建 SessionStateRecovery

**Files:**
- Create: src/browser/recovery.ts
- Test: src/browser/recovery.test.ts

实现状态快照保存和恢复。

---

## Task 5: 改造 pw-session.ts

**Files:**
- Modify: src/browser/pw-session.ts

添加 connectWithFallback, getWatchdog, getRecovery, stopWatchdog 函数。

---

## Task 6: 优化 extension-relay.ts

**Files:**
- Modify: src/browser/extension-relay.ts

优化心跳和空闲超时参数。

---

## Task 7: 集成到 server-context.ts

**Files:**
- Modify: src/browser/server-context.ts

在浏览器初始化时使用双模式连接。

---

## Task 8: 集成测试

**Files:**
- Create: src/browser/auto-reconnect.integration.test.ts

添加集成测试验证整体功能。
