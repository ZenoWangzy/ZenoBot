const DEFAULT_PORT = 18792
const RECONNECT_ALARM = 'openclaw-relay-reconnect'
const RECONNECT_ALARM_PERIOD_MINUTES = 1
const AUTO_ATTACH_RULES_KEY = 'autoAttachRules'
const MAX_AUTO_ATTACH_RULES = 24
const INITIAL_RECONNECT_DELAY_MS = 1000
const MAX_RECONNECT_DELAY_MS = 30000

const BADGE = {
  on: { text: 'ON', color: '#FF5A36' },
  off: { text: '', color: '#000000' },
  connecting: { text: '…', color: '#F59E0B' },
  error: { text: '!', color: '#B91C1C' },
}

/** @type {WebSocket|null} */
let relayWs = null
/** @type {Promise<void>|null} */
let relayConnectPromise = null
/** @type {ReturnType<typeof setTimeout>|null} */
let relayReconnectTimer = null
let relayReconnectDelayMs = INITIAL_RECONNECT_DELAY_MS
let bootstrapStarted = false

let debuggerListenersInstalled = false

let nextSession = 1

/** @type {Map<number, {state:'connecting'|'connected', sessionId?:string, targetId?:string, attachOrder?:number}>} */
const tabs = new Map()
/** @type {Map<string, number>} */
const tabBySession = new Map()
/** @type {Map<string, number>} */
const childSessionToTab = new Map()

/** @type {Map<number, {resolve:(v:any)=>void, reject:(e:Error)=>void}>} */
const pending = new Map()

function nowStack() {
  try {
    return new Error().stack || ''
  } catch {
    return ''
  }
}

async function ensureRelayAndSync() {
  await ensureRelayConnection()
  await restoreAutoAttachedTabs()
  await announceAttachedTabsToRelay()
}

async function autoConnectRelay() {
  try {
    await ensureRelayAndSync()
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    console.warn('auto-connect failed', message)
    increaseRelayBackoff()
    scheduleRelayReconnect()
  }
}

async function bootstrapAutoRelay() {
  if (bootstrapStarted) return
  bootstrapStarted = true
  await ensureReconnectAlarm()
  await autoConnectRelay()
}

function normalizeOrigin(rawUrl) {
  if (typeof rawUrl !== 'string' || rawUrl.trim() === '') return null
  try {
    const parsed = new URL(rawUrl)
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return null
    }
    return `${parsed.protocol}//${parsed.host}`.toLowerCase()
  } catch {
    return null
  }
}

async function loadAutoAttachRules() {
  try {
    const stored = await chrome.storage.local.get([AUTO_ATTACH_RULES_KEY])
    const raw = stored[AUTO_ATTACH_RULES_KEY]
    if (!Array.isArray(raw)) return []
    return raw
      .filter((value) => typeof value === 'string')
      .map((value) => value.trim().toLowerCase())
      .filter(Boolean)
      .slice(0, MAX_AUTO_ATTACH_RULES)
  } catch {
    return []
  }
}

async function saveAutoAttachRules(rules) {
  const normalized = Array.from(
    new Set(
      (rules || [])
        .filter((value) => typeof value === 'string')
        .map((value) => value.trim().toLowerCase())
        .filter(Boolean),
    ),
  ).slice(0, MAX_AUTO_ATTACH_RULES)
  await chrome.storage.local.set({ [AUTO_ATTACH_RULES_KEY]: normalized })
  return normalized
}

async function rememberAutoAttachRuleForTab(tabId) {
  const tab = await chrome.tabs.get(tabId).catch(() => null)
  const origin = normalizeOrigin(tab?.url)
  if (!origin) {
    return
  }
  const rules = await loadAutoAttachRules()
  if (rules.includes(origin)) {
    return
  }
  await saveAutoAttachRules([...rules, origin])
}

async function forgetAutoAttachRuleForTab(tabId) {
  const tab = await chrome.tabs.get(tabId).catch(() => null)
  const origin = normalizeOrigin(tab?.url)
  if (!origin) {
    return
  }
  const rules = await loadAutoAttachRules()
  if (!rules.length) {
    return
  }
  await saveAutoAttachRules(rules.filter((value) => value !== origin))
}

function clearRelayReconnectTimer() {
  if (!relayReconnectTimer) return
  clearTimeout(relayReconnectTimer)
  relayReconnectTimer = null
}

function resetRelayBackoff() {
  relayReconnectDelayMs = INITIAL_RECONNECT_DELAY_MS
}

function increaseRelayBackoff() {
  relayReconnectDelayMs = Math.min(relayReconnectDelayMs * 2, MAX_RECONNECT_DELAY_MS)
}

function scheduleRelayReconnect(delayMs = relayReconnectDelayMs) {
  if (relayReconnectTimer) return
  relayReconnectTimer = setTimeout(() => {
    relayReconnectTimer = null
    void autoConnectRelay()
  }, Math.max(200, delayMs))
}

async function ensureReconnectAlarm() {
  try {
    await chrome.alarms.create(RECONNECT_ALARM, {
      periodInMinutes: RECONNECT_ALARM_PERIOD_MINUTES,
    })
  } catch {
    // ignore
  }
}

async function getRelayPort() {
  const stored = await chrome.storage.local.get(['relayPort'])
  const raw = stored.relayPort
  const n = Number.parseInt(String(raw || ''), 10)
  if (!Number.isFinite(n) || n <= 0 || n > 65535) return DEFAULT_PORT
  return n
}

function setBadge(tabId, kind) {
  const cfg = BADGE[kind]
  void chrome.action.setBadgeText({ tabId, text: cfg.text })
  void chrome.action.setBadgeBackgroundColor({ tabId, color: cfg.color })
  void chrome.action.setBadgeTextColor({ tabId, color: '#FFFFFF' }).catch(() => {})
}

async function ensureRelayConnection() {
  if (relayWs && relayWs.readyState === WebSocket.OPEN) return
  if (relayConnectPromise) return await relayConnectPromise

  relayConnectPromise = (async () => {
    const port = await getRelayPort()
    const httpBase = `http://127.0.0.1:${port}`
    const wsUrl = `ws://127.0.0.1:${port}/extension`

    // Fast preflight: is the relay server up?
    try {
      await fetch(`${httpBase}/`, { method: 'HEAD', signal: AbortSignal.timeout(2000) })
    } catch (err) {
      throw new Error(`Relay server not reachable at ${httpBase} (${String(err)})`)
    }

    const ws = new WebSocket(wsUrl)
    relayWs = ws

    await new Promise((resolve, reject) => {
      const t = setTimeout(() => reject(new Error('WebSocket connect timeout')), 5000)
      ws.onopen = () => {
        clearTimeout(t)
        resolve()
      }
      ws.onerror = () => {
        clearTimeout(t)
        reject(new Error('WebSocket connect failed'))
      }
      ws.onclose = (ev) => {
        clearTimeout(t)
        reject(new Error(`WebSocket closed (${ev.code} ${ev.reason || 'no reason'})`))
      }
    })

    ws.onmessage = (event) => void onRelayMessage(String(event.data || ''))
    ws.onclose = () => onRelayClosed('closed')
    ws.onerror = () => onRelayClosed('error')
    clearRelayReconnectTimer()
    resetRelayBackoff()

    if (!debuggerListenersInstalled) {
      debuggerListenersInstalled = true
      chrome.debugger.onEvent.addListener(onDebuggerEvent)
      chrome.debugger.onDetach.addListener(onDebuggerDetach)
    }
  })()

  try {
    await relayConnectPromise
  } finally {
    relayConnectPromise = null
  }
}

function onRelayClosed(reason) {
  relayWs = null
  for (const [id, p] of pending.entries()) {
    pending.delete(id)
    p.reject(new Error(`Relay disconnected (${reason})`))
  }
  for (const [tabId, tabState] of tabs.entries()) {
    if (tabState?.state === 'connected') {
      tabs.set(tabId, { ...tabState, state: 'connecting' })
    }
    setBadge(tabId, 'connecting')
    void chrome.action.setTitle({
      tabId,
      title: 'OpenClaw Browser Relay: disconnected (auto-reconnecting)',
    })
  }
  childSessionToTab.clear()
  scheduleRelayReconnect()
}

function sendToRelay(payload) {
  const ws = relayWs
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    throw new Error('Relay not connected')
  }
  ws.send(JSON.stringify(payload))
}

async function maybeOpenHelpOnce() {
  try {
    const stored = await chrome.storage.local.get(['helpOnErrorShown'])
    if (stored.helpOnErrorShown === true) return
    await chrome.storage.local.set({ helpOnErrorShown: true })
    await chrome.runtime.openOptionsPage()
  } catch {
    // ignore
  }
}

function requestFromRelay(command) {
  const id = command.id
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject })
    try {
      sendToRelay(command)
    } catch (err) {
      pending.delete(id)
      reject(err instanceof Error ? err : new Error(String(err)))
    }
  })
}

async function pruneMissingAttachedTabs() {
  for (const [tabId, tabState] of tabs.entries()) {
    const exists = await chrome.tabs.get(tabId).catch(() => null)
    if (exists) {
      continue
    }
    if (tabState?.sessionId) {
      tabBySession.delete(tabState.sessionId)
    }
    tabs.delete(tabId)
    for (const [childSessionId, parentTabId] of childSessionToTab.entries()) {
      if (parentTabId === tabId) childSessionToTab.delete(childSessionId)
    }
  }
}

async function restoreAutoAttachedTabs() {
  const ws = relayWs
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    return
  }
  const rules = await loadAutoAttachRules()
  if (!rules.length) {
    return
  }
  const allTabs = await chrome.tabs.query({})
  for (const tab of allTabs) {
    const tabId = tab?.id
    if (!tabId || tabs.has(tabId)) {
      continue
    }
    const origin = normalizeOrigin(tab.url)
    if (!origin || !rules.includes(origin)) {
      continue
    }
    setBadge(tabId, 'connecting')
    try {
      await attachTab(tabId, { skipAttachedEvent: true })
    } catch {
      // ignore best-effort restores (e.g. restricted pages)
    }
  }
}

async function announceAttachedTabsToRelay() {
  const ws = relayWs
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    return
  }
  await pruneMissingAttachedTabs()
  for (const [tabId, tabState] of tabs.entries()) {
    if (!tabState || (tabState.state !== 'connected' && tabState.state !== 'connecting')) {
      continue
    }
    let info
    try {
      info = await chrome.debugger.sendCommand({ tabId }, 'Target.getTargetInfo')
    } catch {
      await detachTab(tabId, 'sync-failed')
      continue
    }
    const targetInfo = info?.targetInfo
    const targetId = String(targetInfo?.targetId || '').trim()
    if (!targetId) {
      continue
    }
    const sessionId = tabState.sessionId || `cb-tab-${nextSession++}`
    tabs.set(tabId, {
      state: 'connected',
      sessionId,
      targetId,
      attachOrder: tabState.attachOrder,
    })
    tabBySession.set(sessionId, tabId)
    setBadge(tabId, 'on')
    void chrome.action.setTitle({
      tabId,
      title: 'OpenClaw Browser Relay: attached (auto-restored)',
    })
    try {
      sendToRelay({
        method: 'forwardCDPEvent',
        params: {
          method: 'Target.attachedToTarget',
          params: {
            sessionId,
            targetInfo: { ...targetInfo, attached: true },
            waitingForDebugger: false,
          },
        },
      })
    } catch {
      // relay might have dropped again; retry loop will handle it
      return
    }
  }
}

async function onRelayMessage(text) {
  /** @type {any} */
  let msg
  try {
    msg = JSON.parse(text)
  } catch {
    return
  }

  if (msg && msg.method === 'ping') {
    try {
      sendToRelay({ method: 'pong' })
    } catch {
      // ignore
    }
    return
  }

  if (msg && typeof msg.id === 'number' && (msg.result !== undefined || msg.error !== undefined)) {
    const p = pending.get(msg.id)
    if (!p) return
    pending.delete(msg.id)
    if (msg.error) p.reject(new Error(String(msg.error)))
    else p.resolve(msg.result)
    return
  }

  if (msg && typeof msg.id === 'number' && msg.method === 'forwardCDPCommand') {
    try {
      const result = await handleForwardCdpCommand(msg)
      sendToRelay({ id: msg.id, result })
    } catch (err) {
      sendToRelay({ id: msg.id, error: err instanceof Error ? err.message : String(err) })
    }
  }
}

function getTabBySessionId(sessionId) {
  const direct = tabBySession.get(sessionId)
  if (direct) return { tabId: direct, kind: 'main' }
  const child = childSessionToTab.get(sessionId)
  if (child) return { tabId: child, kind: 'child' }
  return null
}

function getTabByTargetId(targetId) {
  for (const [tabId, tab] of tabs.entries()) {
    if (tab.targetId === targetId) return tabId
  }
  return null
}

async function attachTab(tabId, opts = {}) {
  const debuggee = { tabId }
  await chrome.debugger.attach(debuggee, '1.3')
  await chrome.debugger.sendCommand(debuggee, 'Page.enable').catch(() => {})

  const info = /** @type {any} */ (await chrome.debugger.sendCommand(debuggee, 'Target.getTargetInfo'))
  const targetInfo = info?.targetInfo
  const targetId = String(targetInfo?.targetId || '').trim()
  if (!targetId) {
    throw new Error('Target.getTargetInfo returned no targetId')
  }

  const sessionId = `cb-tab-${nextSession++}`
  const attachOrder = nextSession

  tabs.set(tabId, { state: 'connected', sessionId, targetId, attachOrder })
  tabBySession.set(sessionId, tabId)
  await rememberAutoAttachRuleForTab(tabId).catch(() => {})
  void chrome.action.setTitle({
    tabId,
    title: 'OpenClaw Browser Relay: attached (click to detach)',
  })

  if (!opts.skipAttachedEvent) {
    sendToRelay({
      method: 'forwardCDPEvent',
      params: {
        method: 'Target.attachedToTarget',
        params: {
          sessionId,
          targetInfo: { ...targetInfo, attached: true },
          waitingForDebugger: false,
        },
      },
    })
  }

  setBadge(tabId, 'on')
  return { sessionId, targetId }
}

async function detachTab(tabId, reason) {
  const tab = tabs.get(tabId)
  if (tab?.sessionId && tab?.targetId) {
    try {
      sendToRelay({
        method: 'forwardCDPEvent',
        params: {
          method: 'Target.detachedFromTarget',
          params: { sessionId: tab.sessionId, targetId: tab.targetId, reason },
        },
      })
    } catch {
      // ignore
    }
  }

  if (tab?.sessionId) tabBySession.delete(tab.sessionId)
  tabs.delete(tabId)

  for (const [childSessionId, parentTabId] of childSessionToTab.entries()) {
    if (parentTabId === tabId) childSessionToTab.delete(childSessionId)
  }

  try {
    await chrome.debugger.detach({ tabId })
  } catch {
    // ignore
  }

  if (reason === 'toggle') {
    await forgetAutoAttachRuleForTab(tabId).catch(() => {})
  }

  setBadge(tabId, 'off')
  void chrome.action.setTitle({
    tabId,
    title: 'OpenClaw Browser Relay (click to attach/detach)',
  })
}

async function connectOrToggleForActiveTab() {
  const [active] = await chrome.tabs.query({ active: true, currentWindow: true })
  const tabId = active?.id
  if (!tabId) return

  const existing = tabs.get(tabId)
  if (existing?.state === 'connected') {
    await detachTab(tabId, 'toggle')
    return
  }

  tabs.set(tabId, { state: 'connecting' })
  setBadge(tabId, 'connecting')
  void chrome.action.setTitle({
    tabId,
    title: 'OpenClaw Browser Relay: connecting to local relay…',
  })

  try {
    await ensureRelayAndSync()
    await attachTab(tabId)
  } catch (err) {
    tabs.delete(tabId)
    setBadge(tabId, 'error')
    void chrome.action.setTitle({
      tabId,
      title: 'OpenClaw Browser Relay: relay not running (open options for setup)',
    })
    void maybeOpenHelpOnce()
    // Extra breadcrumbs in chrome://extensions service worker logs.
    const message = err instanceof Error ? err.message : String(err)
    console.warn('attach failed', message, nowStack())
  }
}

async function handleForwardCdpCommand(msg) {
  const method = String(msg?.params?.method || '').trim()
  const params = msg?.params?.params || undefined
  const sessionId = typeof msg?.params?.sessionId === 'string' ? msg.params.sessionId : undefined

  if (method === 'Target.createTarget') {
    const url = typeof params?.url === 'string' ? params.url : 'about:blank'
    const tab = await chrome.tabs.create({ url, active: false })
    if (!tab.id) throw new Error('Failed to create tab')
    await new Promise((r) => setTimeout(r, 100))
    const attached = await attachTab(tab.id)
    return { targetId: attached.targetId }
  }

  // Map command to tab
  const bySession = sessionId ? getTabBySessionId(sessionId) : null
  const targetId = typeof params?.targetId === 'string' ? params.targetId : undefined
  const tabId =
    bySession?.tabId ||
    (targetId ? getTabByTargetId(targetId) : null) ||
    (() => {
      // No sessionId: pick the first connected tab (stable-ish).
      for (const [id, tab] of tabs.entries()) {
        if (tab.state === 'connected') return id
      }
      return null
    })()

  if (!tabId) throw new Error(`No attached tab for method ${method}`)

  /** @type {chrome.debugger.DebuggerSession} */
  const debuggee = { tabId }

  if (method === 'Runtime.enable') {
    try {
      await chrome.debugger.sendCommand(debuggee, 'Runtime.disable')
      await new Promise((r) => setTimeout(r, 50))
    } catch {
      // ignore
    }
    return await chrome.debugger.sendCommand(debuggee, 'Runtime.enable', params)
  }


  if (method === 'Target.closeTarget') {
    const target = typeof params?.targetId === 'string' ? params.targetId : ''
    const toClose = target ? getTabByTargetId(target) : tabId
    if (!toClose) return { success: false }
    try {
      await chrome.tabs.remove(toClose)
    } catch {
      return { success: false }
    }
    return { success: true }
  }

  if (method === 'Target.activateTarget') {
    const target = typeof params?.targetId === 'string' ? params.targetId : ''
    const toActivate = target ? getTabByTargetId(target) : tabId
    if (!toActivate) return {}
    const tab = await chrome.tabs.get(toActivate).catch(() => null)
    if (!tab) return {}
    if (tab.windowId) {
      await chrome.windows.update(tab.windowId, { focused: true }).catch(() => {})
    }
    await chrome.tabs.update(toActivate, { active: true }).catch(() => {})
    return {}
  }

  const tabState = tabs.get(tabId)
  const mainSessionId = tabState?.sessionId
  const debuggerSession =
    sessionId && mainSessionId && sessionId !== mainSessionId
      ? { ...debuggee, sessionId }
      : debuggee

  return await chrome.debugger.sendCommand(debuggerSession, method, params)
}

function onDebuggerEvent(source, method, params) {
  const tabId = source.tabId
  if (!tabId) return
  const tab = tabs.get(tabId)
  if (!tab?.sessionId) return

  if (method === 'Target.attachedToTarget' && params?.sessionId) {
    childSessionToTab.set(String(params.sessionId), tabId)
  }

  if (method === 'Target.detachedFromTarget' && params?.sessionId) {
    childSessionToTab.delete(String(params.sessionId))
  }

  try {
    sendToRelay({
      method: 'forwardCDPEvent',
      params: {
        sessionId: source.sessionId || tab.sessionId,
        method,
        params,
      },
    })
  } catch {
    // ignore
  }
}

function onDebuggerDetach(source, reason) {
  const tabId = source.tabId
  if (!tabId) return
  if (!tabs.has(tabId)) return
  void detachTab(tabId, reason)
}

chrome.action.onClicked.addListener(() => void connectOrToggleForActiveTab())

chrome.tabs.onRemoved.addListener((tabId) => {
  if (!tabs.has(tabId)) return
  void detachTab(tabId, 'tab-removed')
})

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (!changeInfo.url && changeInfo.status !== 'complete') {
    return
  }
  void (async () => {
    if (tabs.has(tabId)) return
    const origin = normalizeOrigin(tab?.url || changeInfo.url)
    if (!origin) return
    const rules = await loadAutoAttachRules()
    if (!rules.includes(origin)) return
    try {
      await ensureRelayAndSync()
      if (!tabs.has(tabId)) {
        await attachTab(tabId)
      }
    } catch {
      // ignore; periodic alarm/auto-reconnect will retry
    }
  })()
})

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name !== RECONNECT_ALARM) return
  if (relayWs && relayWs.readyState === WebSocket.OPEN) return
  void autoConnectRelay()
})

if (chrome.runtime.onStartup) {
  chrome.runtime.onStartup.addListener(() => void bootstrapAutoRelay())
}

chrome.runtime.onInstalled.addListener(() => {
  void ensureReconnectAlarm()
  void autoConnectRelay()
  // Useful: first-time instructions.
  void chrome.runtime.openOptionsPage()
})

void bootstrapAutoRelay()
