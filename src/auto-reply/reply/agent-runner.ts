import crypto from "node:crypto";
import fs from "node:fs";
import type { TypingMode } from "../../config/types.js";
import type { OriginatingChannelType, TemplateContext } from "../templating.js";
import type { GetReplyOptions, ReplyPayload } from "../types.js";
import type { TypingController } from "./typing.js";
import { lookupContextTokens } from "../../agents/context.js";
import { DEFAULT_CONTEXT_TOKENS } from "../../agents/defaults.js";
import { resolveModelAuthMode } from "../../agents/model-auth.js";
import { isCliProvider } from "../../agents/model-selection.js";
import { queueEmbeddedPiMessage } from "../../agents/pi-embedded.js";
import { hasNonzeroUsage } from "../../agents/usage.js";
import {
  resolveAgentIdFromSessionKey,
  resolveSessionFilePath,
  resolveSessionTranscriptPath,
  type SessionEntry,
  updateSessionStore,
  updateSessionStoreEntry,
} from "../../config/sessions.js";
import { parseDurationMs } from "../../cli/parse-duration.js";
import { emitDiagnosticEvent, isDiagnosticsEnabled } from "../../infra/diagnostic-events.js";
import { logVerbose } from "../../globals.js";
import { defaultRuntime } from "../../runtime.js";
import { estimateUsageCost, resolveModelCostConfig } from "../../utils/usage-format.js";
import { resolveResponseUsageMode, type VerboseLevel } from "../thinking.js";
import { runAgentTurnWithFallback } from "./agent-runner-execution.js";
import {
  createShouldEmitToolOutput,
  createShouldEmitToolResult,
  finalizeWithFollowup,
  isAudioPayload,
  signalTypingIfNeeded,
} from "./agent-runner-helpers.js";
import { runMemoryFlushIfNeeded } from "./agent-runner-memory.js";
import { buildReplyPayloads } from "./agent-runner-payloads.js";
import { appendUsageLine, formatResponseUsageLine } from "./agent-runner-utils.js";
import { createAudioAsVoiceBuffer, createBlockReplyPipeline } from "./block-reply-pipeline.js";
import { resolveBlockStreamingCoalescing } from "./block-streaming.js";
import { createFollowupRunner } from "./followup-runner.js";
import { enqueueFollowupRun, type FollowupRun, type QueueSettings } from "./queue.js";
import { createReplyToModeFilterForChannel, resolveReplyToMode } from "./reply-threading.js";
import { incrementRunCompactionCount, persistRunSessionUsage } from "./session-run-accounting.js";
import { createTypingSignaler } from "./typing-mode.js";

const BLOCK_REPLY_SEND_TIMEOUT_MS = 15_000;
const PROGRESS_UPDATE_DEFAULT_INTERVAL_MS = 30_000;
const PROGRESS_UPDATE_MIN_INTERVAL_MS = 10_000;
const PROGRESS_DUPLICATE_RESEND_MS = 60_000;

export async function runReplyAgent(params: {
  commandBody: string;
  followupRun: FollowupRun;
  queueKey: string;
  resolvedQueue: QueueSettings;
  shouldSteer: boolean;
  shouldFollowup: boolean;
  isActive: boolean;
  isStreaming: boolean;
  opts?: GetReplyOptions;
  typing: TypingController;
  sessionEntry?: SessionEntry;
  sessionStore?: Record<string, SessionEntry>;
  sessionKey?: string;
  storePath?: string;
  defaultModel: string;
  agentCfgContextTokens?: number;
  resolvedVerboseLevel: VerboseLevel;
  isNewSession: boolean;
  blockStreamingEnabled: boolean;
  blockReplyChunking?: {
    minChars: number;
    maxChars: number;
    breakPreference: "paragraph" | "newline" | "sentence";
    flushOnParagraph?: boolean;
  };
  resolvedBlockStreamingBreak: "text_end" | "message_end";
  sessionCtx: TemplateContext;
  shouldInjectGroupIntro: boolean;
  typingMode: TypingMode;
}): Promise<ReplyPayload | ReplyPayload[] | undefined> {
  const {
    commandBody,
    followupRun,
    queueKey,
    resolvedQueue,
    shouldSteer,
    shouldFollowup,
    isActive,
    isStreaming,
    opts,
    typing,
    sessionEntry,
    sessionStore,
    sessionKey,
    storePath,
    defaultModel,
    agentCfgContextTokens,
    resolvedVerboseLevel,
    isNewSession,
    blockStreamingEnabled,
    blockReplyChunking,
    resolvedBlockStreamingBreak,
    sessionCtx,
    shouldInjectGroupIntro,
    typingMode,
  } = params;

  let activeSessionEntry = sessionEntry;
  const activeSessionStore = sessionStore;
  let activeIsNewSession = isNewSession;

  const isHeartbeat = opts?.isHeartbeat === true;
  const typingSignals = createTypingSignaler({
    typing,
    mode: typingMode,
    isHeartbeat,
  });

  const shouldEmitToolResult = createShouldEmitToolResult({
    sessionKey,
    storePath,
    resolvedVerboseLevel,
  });
  const shouldEmitToolOutput = createShouldEmitToolOutput({
    sessionKey,
    storePath,
    resolvedVerboseLevel,
  });

  const pendingToolTasks = new Set<Promise<void>>();
  const blockReplyTimeoutMs = opts?.blockReplyTimeoutMs ?? BLOCK_REPLY_SEND_TIMEOUT_MS;
  const progressConfig = followupRun.run.config?.agents?.defaults?.progressMessages;
  const shouldSendProgressUpdates =
    !isHeartbeat && progressConfig?.enabled === true && Boolean(opts?.onProgressUpdate);
  const progressIntervalRaw = progressConfig?.interval?.trim();
  const progressTemplateRaw = progressConfig?.template?.trim();
  const progressTemplate = progressTemplateRaw && progressTemplateRaw.length > 0 ? progressTemplateRaw : undefined;
  const quietAfterMs = Math.max(0, (progressConfig?.quietAfterSeconds ?? 0) * 1000);
  const statusChangeImmediate = progressConfig?.statusChangeImmediate === true;
  let progressIntervalMs = PROGRESS_UPDATE_DEFAULT_INTERVAL_MS;
  if (progressIntervalRaw) {
    try {
      progressIntervalMs = parseDurationMs(progressIntervalRaw, { defaultUnit: "s" });
    } catch (err) {
      logVerbose(
        `Invalid agents.defaults.progressMessages.interval "${progressIntervalRaw}": ${String(err)}. Falling back to 30s.`,
      );
    }
  }
  progressIntervalMs = Math.max(PROGRESS_UPDATE_MIN_INTERVAL_MS, progressIntervalMs);
  let progressTimer: NodeJS.Timeout | undefined;
  let progressStopped = false;
  let progressStatusLabel: string | undefined;
  let progressPhase = "thinking";
  let progressToolName: string | undefined;
  const progressStartedAt = Date.now();
  let lastVisibleActivityAt = progressStartedAt;
  let lastProgressMessage = "";
  let lastProgressSentAt = 0;
  const markVisibleActivity = () => {
    lastVisibleActivityAt = Date.now();
  };
  const formatProgressStatus = () => {
    const elapsedMs = Math.max(1, Date.now() - progressStartedAt);
    const elapsedSec = Math.max(1, Math.floor((Date.now() - progressStartedAt) / 1000));
    if (progressTemplate) {
      const rendered = progressTemplate
        .replaceAll("{elapsedMs}", String(elapsedMs))
        .replaceAll("{elapsedSeconds}", String(elapsedSec))
        .replaceAll("{status}", progressStatusLabel ?? "")
        .replaceAll("{phase}", progressPhase)
        .replaceAll("{tool}", progressToolName ?? "")
        .trim();
      if (rendered) {
        return rendered;
      }
    }
    const detail = progressStatusLabel ? ` · ${progressStatusLabel}` : "";
    return `⏳ Still working (${elapsedSec}s)${detail}.`;
  };
  const queueProgressUpdate = () => {
    if (!shouldSendProgressUpdates || progressStopped) {
      return;
    }
    if (quietAfterMs > 0 && Date.now() - lastVisibleActivityAt < quietAfterMs) {
      return;
    }
    const messageText = formatProgressStatus();
    const now = Date.now();
    if (
      messageText === lastProgressMessage &&
      now - lastProgressSentAt < PROGRESS_DUPLICATE_RESEND_MS
    ) {
      return;
    }
    void Promise.resolve(
      opts?.onProgressUpdate?.({
        text: messageText,
      }),
    )
      .then(() => {
        lastProgressMessage = messageText;
        lastProgressSentAt = now;
        markVisibleActivity();
      })
      .catch((err) => {
        logVerbose(`progress update delivery failed: ${String(err)}`);
      });
  };
  const maybeQueueImmediateProgress = (previous: {
    status?: string;
    phase: string;
    tool?: string;
  }) => {
    if (!statusChangeImmediate) {
      return;
    }
    if (
      previous.status !== progressStatusLabel ||
      previous.phase !== progressPhase ||
      previous.tool !== progressToolName
    ) {
      queueProgressUpdate();
    }
  };
  const updateProgressStatusFromEvent = (evt: { stream: string; data: Record<string, unknown> }) => {
    if (!shouldSendProgressUpdates) {
      return;
    }
    const previous = {
      status: progressStatusLabel,
      phase: progressPhase,
      tool: progressToolName,
    };
    if (evt.stream === "tool") {
      const phase = typeof evt.data.phase === "string" ? evt.data.phase : "";
      const name = typeof evt.data.name === "string" ? evt.data.name : undefined;
      if (phase === "start" || phase === "update") {
        progressPhase = phase === "start" ? "tool_start" : "tool_update";
        progressToolName = name;
        progressStatusLabel = name ? `running tool: ${name}` : "running tool";
      } else if (phase === "result") {
        progressPhase = "tool_result";
        progressToolName = name;
        const isError = Boolean(evt.data.isError);
        progressStatusLabel = isError
          ? name
            ? `tool failed: ${name}`
            : "tool failed"
          : name
            ? `tool done: ${name}`
            : "tool completed";
      }
      maybeQueueImmediateProgress(previous);
      return;
    }
    if (evt.stream === "compaction") {
      const phase = typeof evt.data.phase === "string" ? evt.data.phase : "";
      if (phase === "start") {
        progressPhase = "compaction_start";
        progressToolName = undefined;
        progressStatusLabel = "compacting session";
      } else if (phase === "end") {
        progressPhase = "compaction_end";
        progressToolName = undefined;
        progressStatusLabel = "compaction complete";
      }
      maybeQueueImmediateProgress(previous);
      return;
    }
    if (evt.stream === "assistant") {
      const delta = typeof evt.data.delta === "string" ? evt.data.delta.trim() : "";
      const mediaUrls = Array.isArray(evt.data.mediaUrls) ? evt.data.mediaUrls : [];
      if (delta || mediaUrls.length > 0) {
        progressPhase = "assistant_stream";
        progressToolName = undefined;
        progressStatusLabel = "drafting response";
        markVisibleActivity();
      }
      maybeQueueImmediateProgress(previous);
      return;
    }
    if (evt.stream === "lifecycle") {
      const phase = typeof evt.data.phase === "string" ? evt.data.phase : "";
      if (phase === "start") {
        progressPhase = "lifecycle_start";
        progressToolName = undefined;
        progressStatusLabel = "thinking";
      } else if (phase === "end") {
        progressPhase = "lifecycle_end";
        progressToolName = undefined;
        progressStatusLabel = "finalizing response";
      } else if (phase === "error") {
        progressPhase = "lifecycle_error";
        progressToolName = undefined;
        progressStatusLabel = "run error";
      }
      maybeQueueImmediateProgress(previous);
    }
  };
  if (shouldSendProgressUpdates) {
    progressTimer = setInterval(() => {
      queueProgressUpdate();
    }, progressIntervalMs);
  }

  const replyToChannel =
    sessionCtx.OriginatingChannel ??
    ((sessionCtx.Surface ?? sessionCtx.Provider)?.toLowerCase() as
      | OriginatingChannelType
      | undefined);
  const replyToMode = resolveReplyToMode(
    followupRun.run.config,
    replyToChannel,
    sessionCtx.AccountId,
    sessionCtx.ChatType,
  );
  const applyReplyToMode = createReplyToModeFilterForChannel(replyToMode, replyToChannel);
  const cfg = followupRun.run.config;
  const blockReplyCoalescing =
    blockStreamingEnabled && opts?.onBlockReply
      ? resolveBlockStreamingCoalescing(
          cfg,
          sessionCtx.Provider,
          sessionCtx.AccountId,
          blockReplyChunking,
        )
      : undefined;
  const blockReplyPipeline =
    blockStreamingEnabled && opts?.onBlockReply
      ? createBlockReplyPipeline({
          onBlockReply: opts.onBlockReply,
          timeoutMs: blockReplyTimeoutMs,
          coalescing: blockReplyCoalescing,
          buffer: createAudioAsVoiceBuffer({ isAudioPayload }),
        })
      : null;

  if (shouldSteer && isStreaming) {
    const steered = queueEmbeddedPiMessage(followupRun.run.sessionId, followupRun.prompt);
    if (steered && !shouldFollowup) {
      if (activeSessionEntry && activeSessionStore && sessionKey) {
        const updatedAt = Date.now();
        activeSessionEntry.updatedAt = updatedAt;
        activeSessionStore[sessionKey] = activeSessionEntry;
        if (storePath) {
          await updateSessionStoreEntry({
            storePath,
            sessionKey,
            update: async () => ({ updatedAt }),
          });
        }
      }
      typing.cleanup();
      return undefined;
    }
  }

  if (isActive && (shouldFollowup || resolvedQueue.mode === "steer")) {
    enqueueFollowupRun(queueKey, followupRun, resolvedQueue);
    if (activeSessionEntry && activeSessionStore && sessionKey) {
      const updatedAt = Date.now();
      activeSessionEntry.updatedAt = updatedAt;
      activeSessionStore[sessionKey] = activeSessionEntry;
      if (storePath) {
        await updateSessionStoreEntry({
          storePath,
          sessionKey,
          update: async () => ({ updatedAt }),
        });
      }
    }
    typing.cleanup();
    return undefined;
  }

  await typingSignals.signalRunStart();

  activeSessionEntry = await runMemoryFlushIfNeeded({
    cfg,
    followupRun,
    sessionCtx,
    opts,
    defaultModel,
    agentCfgContextTokens,
    resolvedVerboseLevel,
    sessionEntry: activeSessionEntry,
    sessionStore: activeSessionStore,
    sessionKey,
    storePath,
    isHeartbeat,
  });

  const runFollowupTurn = createFollowupRunner({
    opts,
    typing,
    typingMode,
    sessionEntry: activeSessionEntry,
    sessionStore: activeSessionStore,
    sessionKey,
    storePath,
    defaultModel,
    agentCfgContextTokens,
  });

  let responseUsageLine: string | undefined;
  type SessionResetOptions = {
    failureLabel: string;
    buildLogMessage: (nextSessionId: string) => string;
    cleanupTranscripts?: boolean;
  };
  const resetSession = async ({
    failureLabel,
    buildLogMessage,
    cleanupTranscripts,
  }: SessionResetOptions): Promise<boolean> => {
    if (!sessionKey || !activeSessionStore || !storePath) {
      return false;
    }
    const prevEntry = activeSessionStore[sessionKey] ?? activeSessionEntry;
    if (!prevEntry) {
      return false;
    }
    const prevSessionId = cleanupTranscripts ? prevEntry.sessionId : undefined;
    const nextSessionId = crypto.randomUUID();
    const nextEntry: SessionEntry = {
      ...prevEntry,
      sessionId: nextSessionId,
      updatedAt: Date.now(),
      systemSent: false,
      abortedLastRun: false,
    };
    const agentId = resolveAgentIdFromSessionKey(sessionKey);
    const nextSessionFile = resolveSessionTranscriptPath(
      nextSessionId,
      agentId,
      sessionCtx.MessageThreadId,
    );
    nextEntry.sessionFile = nextSessionFile;
    activeSessionStore[sessionKey] = nextEntry;
    try {
      await updateSessionStore(storePath, (store) => {
        store[sessionKey] = nextEntry;
      });
    } catch (err) {
      defaultRuntime.error(
        `Failed to persist session reset after ${failureLabel} (${sessionKey}): ${String(err)}`,
      );
    }
    followupRun.run.sessionId = nextSessionId;
    followupRun.run.sessionFile = nextSessionFile;
    activeSessionEntry = nextEntry;
    activeIsNewSession = true;
    defaultRuntime.error(buildLogMessage(nextSessionId));
    if (cleanupTranscripts && prevSessionId) {
      const transcriptCandidates = new Set<string>();
      const resolved = resolveSessionFilePath(prevSessionId, prevEntry, { agentId });
      if (resolved) {
        transcriptCandidates.add(resolved);
      }
      transcriptCandidates.add(resolveSessionTranscriptPath(prevSessionId, agentId));
      for (const candidate of transcriptCandidates) {
        try {
          fs.unlinkSync(candidate);
        } catch {
          // Best-effort cleanup.
        }
      }
    }
    return true;
  };
  const resetSessionAfterCompactionFailure = async (reason: string): Promise<boolean> =>
    resetSession({
      failureLabel: "compaction failure",
      buildLogMessage: (nextSessionId) =>
        `Auto-compaction failed (${reason}). Restarting session ${sessionKey} -> ${nextSessionId} and retrying.`,
    });
  const resetSessionAfterRoleOrderingConflict = async (reason: string): Promise<boolean> =>
    resetSession({
      failureLabel: "role ordering conflict",
      buildLogMessage: (nextSessionId) =>
        `Role ordering conflict (${reason}). Restarting session ${sessionKey} -> ${nextSessionId}.`,
      cleanupTranscripts: true,
    });
  const optsWithVisibilityTracking: GetReplyOptions | undefined = opts
    ? {
        ...opts,
        onPartialReply: async (payload) => {
          markVisibleActivity();
          return await opts.onPartialReply?.(payload);
        },
        onReasoningStream: async (payload) => {
          markVisibleActivity();
          return await opts.onReasoningStream?.(payload);
        },
        onBlockReply: async (payload, context) => {
          markVisibleActivity();
          return await opts.onBlockReply?.(payload, context);
        },
        onToolResult: async (payload) => {
          markVisibleActivity();
          return await opts.onToolResult?.(payload);
        },
      }
    : undefined;
  try {
    const runStartedAt = Date.now();
    const runOutcome = await runAgentTurnWithFallback({
      commandBody,
      followupRun,
      sessionCtx,
      opts: optsWithVisibilityTracking,
      typingSignals,
      blockReplyPipeline,
      blockStreamingEnabled,
      blockReplyChunking,
      resolvedBlockStreamingBreak,
      applyReplyToMode,
      shouldEmitToolResult,
      shouldEmitToolOutput,
      pendingToolTasks,
      resetSessionAfterCompactionFailure,
      resetSessionAfterRoleOrderingConflict,
      isHeartbeat,
      sessionKey,
      getActiveSessionEntry: () => activeSessionEntry,
      activeSessionStore,
      storePath,
      resolvedVerboseLevel,
      onRunEvent: updateProgressStatusFromEvent,
    });

    if (runOutcome.kind === "final") {
      return finalizeWithFollowup(runOutcome.payload, queueKey, runFollowupTurn);
    }

    const { runResult, fallbackProvider, fallbackModel, directlySentBlockKeys } = runOutcome;
    let { didLogHeartbeatStrip, autoCompactionCompleted } = runOutcome;

    if (
      shouldInjectGroupIntro &&
      activeSessionEntry &&
      activeSessionStore &&
      sessionKey &&
      activeSessionEntry.groupActivationNeedsSystemIntro
    ) {
      const updatedAt = Date.now();
      activeSessionEntry.groupActivationNeedsSystemIntro = false;
      activeSessionEntry.updatedAt = updatedAt;
      activeSessionStore[sessionKey] = activeSessionEntry;
      if (storePath) {
        await updateSessionStoreEntry({
          storePath,
          sessionKey,
          update: async () => ({
            groupActivationNeedsSystemIntro: false,
            updatedAt,
          }),
        });
      }
    }

    const payloadArray = runResult.payloads ?? [];

    if (blockReplyPipeline) {
      await blockReplyPipeline.flush({ force: true });
      blockReplyPipeline.stop();
    }
    if (pendingToolTasks.size > 0) {
      await Promise.allSettled(pendingToolTasks);
    }

    const usage = runResult.meta.agentMeta?.usage;
    const promptTokens = runResult.meta.agentMeta?.promptTokens;
    const modelUsed = runResult.meta.agentMeta?.model ?? fallbackModel ?? defaultModel;
    const providerUsed =
      runResult.meta.agentMeta?.provider ?? fallbackProvider ?? followupRun.run.provider;
    const cliSessionId = isCliProvider(providerUsed, cfg)
      ? runResult.meta.agentMeta?.sessionId?.trim()
      : undefined;
    const contextTokensUsed =
      agentCfgContextTokens ??
      lookupContextTokens(modelUsed) ??
      activeSessionEntry?.contextTokens ??
      DEFAULT_CONTEXT_TOKENS;

    await persistRunSessionUsage({
      storePath,
      sessionKey,
      usage,
      lastCallUsage: runResult.meta.agentMeta?.lastCallUsage,
      promptTokens,
      modelUsed,
      providerUsed,
      contextTokensUsed,
      systemPromptReport: runResult.meta.systemPromptReport,
      cliSessionId,
    });

    // Drain any late tool/block deliveries before deciding there's "nothing to send".
    // Otherwise, a late typing trigger (e.g. from a tool callback) can outlive the run and
    // keep the typing indicator stuck.
    if (payloadArray.length === 0) {
      return finalizeWithFollowup(undefined, queueKey, runFollowupTurn);
    }

    const payloadResult = buildReplyPayloads({
      payloads: payloadArray,
      isHeartbeat,
      didLogHeartbeatStrip,
      blockStreamingEnabled,
      blockReplyPipeline,
      directlySentBlockKeys,
      replyToMode,
      replyToChannel,
      currentMessageId: sessionCtx.MessageSidFull ?? sessionCtx.MessageSid,
      messageProvider: followupRun.run.messageProvider,
      messagingToolSentTexts: runResult.messagingToolSentTexts,
      messagingToolSentTargets: runResult.messagingToolSentTargets,
      originatingTo: sessionCtx.OriginatingTo ?? sessionCtx.To,
      accountId: sessionCtx.AccountId,
    });
    const { replyPayloads } = payloadResult;
    didLogHeartbeatStrip = payloadResult.didLogHeartbeatStrip;

    if (replyPayloads.length === 0) {
      return finalizeWithFollowup(undefined, queueKey, runFollowupTurn);
    }

    await signalTypingIfNeeded(replyPayloads, typingSignals);

    if (isDiagnosticsEnabled(cfg) && hasNonzeroUsage(usage)) {
      const input = usage.input ?? 0;
      const output = usage.output ?? 0;
      const cacheRead = usage.cacheRead ?? 0;
      const cacheWrite = usage.cacheWrite ?? 0;
      const promptTokens = input + cacheRead + cacheWrite;
      const totalTokens = usage.total ?? promptTokens + output;
      const costConfig = resolveModelCostConfig({
        provider: providerUsed,
        model: modelUsed,
        config: cfg,
      });
      const costUsd = estimateUsageCost({ usage, cost: costConfig });
      emitDiagnosticEvent({
        type: "model.usage",
        sessionKey,
        sessionId: followupRun.run.sessionId,
        channel: replyToChannel,
        provider: providerUsed,
        model: modelUsed,
        usage: {
          input,
          output,
          cacheRead,
          cacheWrite,
          promptTokens,
          total: totalTokens,
        },
        context: {
          limit: contextTokensUsed,
          used: totalTokens,
        },
        costUsd,
        durationMs: Date.now() - runStartedAt,
      });
    }

    const responseUsageRaw =
      activeSessionEntry?.responseUsage ??
      (sessionKey ? activeSessionStore?.[sessionKey]?.responseUsage : undefined);
    const responseUsageMode = resolveResponseUsageMode(responseUsageRaw);
    if (responseUsageMode !== "off" && hasNonzeroUsage(usage)) {
      const authMode = resolveModelAuthMode(providerUsed, cfg);
      const showCost = authMode === "api-key";
      const costConfig = showCost
        ? resolveModelCostConfig({
            provider: providerUsed,
            model: modelUsed,
            config: cfg,
          })
        : undefined;
      let formatted = formatResponseUsageLine({
        usage,
        showCost,
        costConfig,
      });
      if (formatted && responseUsageMode === "full" && sessionKey) {
        formatted = `${formatted} · session ${sessionKey}`;
      }
      if (formatted) {
        responseUsageLine = formatted;
      }
    }

    // If verbose is enabled and this is a new session, prepend a session hint.
    let finalPayloads = replyPayloads;
    const verboseEnabled = resolvedVerboseLevel !== "off";
    if (autoCompactionCompleted) {
      const count = await incrementRunCompactionCount({
        sessionEntry: activeSessionEntry,
        sessionStore: activeSessionStore,
        sessionKey,
        storePath,
        lastCallUsage: runResult.meta.agentMeta?.lastCallUsage,
        contextTokensUsed,
      });
      if (verboseEnabled) {
        const suffix = typeof count === "number" ? ` (count ${count})` : "";
        finalPayloads = [{ text: `🧹 Auto-compaction complete${suffix}.` }, ...finalPayloads];
      }
    }
    if (verboseEnabled && activeIsNewSession) {
      finalPayloads = [{ text: `🧭 New session: ${followupRun.run.sessionId}` }, ...finalPayloads];
    }
    if (responseUsageLine) {
      finalPayloads = appendUsageLine(finalPayloads, responseUsageLine);
    }

    return finalizeWithFollowup(
      finalPayloads.length === 1 ? finalPayloads[0] : finalPayloads,
      queueKey,
      runFollowupTurn,
    );
  } finally {
    progressStopped = true;
    if (progressTimer) {
      clearInterval(progressTimer);
      progressTimer = undefined;
    }
    blockReplyPipeline?.stop();
    typing.markRunComplete();
  }
}
