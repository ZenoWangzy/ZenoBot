/**
 * Session memory hook handler
 *
 * Saves session context to memory when /new command is triggered.
 * Produces structured memory files with category, importance, and tags
 * metadata so the vector index can filter and rank results.
 */

import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import type { OpenClawConfig } from "../../../config/config.js";
import type { MemoryCategory, MemoryImportance } from "../../../memory/memory-categories.js";
import type { HookHandler } from "../../hooks.js";
import { resolveAgentWorkspaceDir } from "../../../agents/agent-scope.js";
import { resolveStateDir } from "../../../config/paths.js";
import { createSubsystemLogger } from "../../../logging/subsystem.js";
import { resolveAgentIdFromSessionKey } from "../../../routing/session-key.js";
import { hasInterSessionUserProvenance } from "../../../sessions/input-provenance.js";
import { resolveHookConfig } from "../../config.js";
import { generateSlugViaLLM } from "../../llm-slug-generator.js";

const log = createSubsystemLogger("hooks/session-memory");

/**
 * Read recent messages from session file for slug generation
 */
async function getRecentSessionContent(
  sessionFilePath: string,
  messageCount: number = 15,
): Promise<string | null> {
  try {
    const content = await fs.readFile(sessionFilePath, "utf-8");
    const lines = content.trim().split("\n");

    // Parse JSONL and extract user/assistant messages first
    const allMessages: string[] = [];
    for (const line of lines) {
      try {
        const entry = JSON.parse(line);
        // Session files have entries with type="message" containing a nested message object
        if (entry.type === "message" && entry.message) {
          const msg = entry.message;
          const role = msg.role;
          if ((role === "user" || role === "assistant") && msg.content) {
            if (role === "user" && hasInterSessionUserProvenance(msg)) {
              continue;
            }
            // Extract text content
            const text = Array.isArray(msg.content)
              ? // oxlint-disable-next-line typescript/no-explicit-any
                msg.content.find((c: any) => c.type === "text")?.text
              : msg.content;
            if (text && !text.startsWith("/")) {
              allMessages.push(`${role}: ${text}`);
            }
          }
        }
      } catch {
        // Skip invalid JSON lines
      }
    }

    // Then slice to get exactly messageCount messages
    const recentMessages = allMessages.slice(-messageCount);
    return recentMessages.join("\n");
  } catch {
    return null;
  }
}

/**
 * Save session context to memory when /new command is triggered
 */
const saveSessionToMemory: HookHandler = async (event) => {
  // Only trigger on 'new' command
  if (event.type !== "command" || event.action !== "new") {
    return;
  }

  try {
    log.debug("Hook triggered for /new command");

    const context = event.context || {};
    const cfg = context.cfg as OpenClawConfig | undefined;
    const agentId = resolveAgentIdFromSessionKey(event.sessionKey);
    const workspaceDir = cfg
      ? resolveAgentWorkspaceDir(cfg, agentId)
      : path.join(resolveStateDir(process.env, os.homedir), "workspace");
    const memoryDir = path.join(workspaceDir, "memory");
    await fs.mkdir(memoryDir, { recursive: true });

    // Get today's date for filename
    const now = new Date(event.timestamp);
    const dateStr = now.toISOString().split("T")[0]; // YYYY-MM-DD

    // Generate descriptive slug from session using LLM
    const sessionEntry = (context.previousSessionEntry || context.sessionEntry || {}) as Record<
      string,
      unknown
    >;
    const currentSessionId = sessionEntry.sessionId as string;
    const currentSessionFile = sessionEntry.sessionFile as string;

    log.debug("Session context resolved", {
      sessionId: currentSessionId,
      sessionFile: currentSessionFile,
      hasCfg: Boolean(cfg),
    });

    const sessionFile = currentSessionFile || undefined;

    // Read message count from hook config (default: 15)
    const hookConfig = resolveHookConfig(cfg, "session-memory");
    const messageCount =
      typeof hookConfig?.messages === "number" && hookConfig.messages > 0
        ? hookConfig.messages
        : 15;

    let slug: string | null = null;
    let sessionContent: string | null = null;

    if (sessionFile) {
      // Get recent conversation content
      sessionContent = await getRecentSessionContent(sessionFile, messageCount);
      log.debug("Session content loaded", {
        length: sessionContent?.length ?? 0,
        messageCount,
      });

      // Avoid calling the model provider in unit tests; keep hooks fast and deterministic.
      const isTestEnv =
        process.env.OPENCLAW_TEST_FAST === "1" ||
        process.env.VITEST === "true" ||
        process.env.VITEST === "1" ||
        process.env.NODE_ENV === "test";
      const allowLlmSlug = !isTestEnv && hookConfig?.llmSlug !== false;

      if (sessionContent && cfg && allowLlmSlug) {
        log.debug("Calling generateSlugViaLLM...");
        // Use LLM to generate a descriptive slug
        slug = await generateSlugViaLLM({ sessionContent, cfg });
        log.debug("Generated slug", { slug });
      }
    }

    // If no slug, use timestamp
    if (!slug) {
      const timeSlug = now.toISOString().split("T")[1].split(".")[0].replace(/:/g, "");
      slug = timeSlug.slice(0, 4); // HHMM
      log.debug("Using fallback timestamp slug", { slug });
    }

    // Create filename with date and slug
    const filename = `${dateStr}-${slug}.md`;
    const memoryFilePath = path.join(memoryDir, filename);
    log.debug("Memory file path resolved", {
      filename,
      path: memoryFilePath.replace(os.homedir(), "~"),
    });

    // Format time as HH:MM:SS UTC
    const timeStr = now.toISOString().split("T")[1].split(".")[0];

    // Extract context details
    const sessionId = (sessionEntry.sessionId as string) || "unknown";
    const source = (context.commandSource as string) || "unknown";

    // Classify session content to extract structured metadata
    const classification = classifySessionContent(sessionContent);

    // Build structured Markdown entry
    const entryParts = [
      `# ${dateStr}: ${slug}`,
      `tags: ${classification.tags.map((t) => `#${t}`).join(" ") || "#session"}`,
      `importance: ${classification.importance}`,
      `category: ${classification.category}`,
      "",
      `- **Session Key**: ${event.sessionKey}`,
      `- **Session ID**: ${sessionId}`,
      `- **Source**: ${source}`,
      `- **Time**: ${timeStr} UTC`,
      "",
    ];

    // Include conversation content if available
    if (sessionContent) {
      entryParts.push(
        `## ${CATEGORY_LABELS[classification.category] ?? "Summary"}`,
        "",
        sessionContent,
        "",
      );
    }

    const entry = entryParts.join("\n");

    // Write to new memory file
    await fs.writeFile(memoryFilePath, entry, "utf-8");
    log.debug("Memory file written successfully");

    // Log completion (but don't send user-visible confirmation - it's internal housekeeping)
    const relPath = memoryFilePath.replace(os.homedir(), "~");
    log.info(`Session context saved to ${relPath}`);
  } catch (err) {
    if (err instanceof Error) {
      log.error("Failed to save session memory", {
        errorName: err.name,
        errorMessage: err.message,
        stack: err.stack,
      });
    } else {
      log.error("Failed to save session memory", { error: String(err) });
    }
  }
};

// ---------------------------------------------------------------------------
// Classification helpers
// ---------------------------------------------------------------------------

const CATEGORY_LABELS: Record<MemoryCategory, string> = {
  decision: "Decision",
  action: "Action Items",
  preference: "Preferences",
  context: "Context",
  note: "Conversation Summary",
};

const DECISION_KEYWORDS = [
  "decided",
  "decision",
  "chose",
  "选择",
  "决定",
  "agreed",
  "approve",
  "settled",
  "conclusion",
  "结论",
  "方案",
];
const ACTION_KEYWORDS = [
  "todo",
  "action",
  "task",
  "deadline",
  "待办",
  "任务",
  "implement",
  "fix",
  "build",
  "deploy",
  "ship",
  "create",
];
const PREFERENCE_KEYWORDS = [
  "prefer",
  "like",
  "always",
  "never",
  "偏好",
  "喜欢",
  "style",
  "convention",
];

/**
 * Best-effort heuristic classification of session content.
 *
 * This runs synchronously and does not call the LLM — it is a fast
 * fallback that tags the memory file with reasonable metadata even when
 * the model is unavailable.
 */
function classifySessionContent(content: string | null): {
  category: MemoryCategory;
  importance: MemoryImportance;
  tags: string[];
} {
  if (!content) {
    return { category: "note", importance: "low", tags: ["session"] };
  }

  const lower = content.toLowerCase();
  const tags: string[] = ["session"];
  let category: MemoryCategory = "note";
  let importance: MemoryImportance = "medium";

  const hasDecision = DECISION_KEYWORDS.some((kw) => lower.includes(kw));
  const hasAction = ACTION_KEYWORDS.some((kw) => lower.includes(kw));
  const hasPreference = PREFERENCE_KEYWORDS.some((kw) => lower.includes(kw));

  if (hasDecision) {
    category = "decision";
    importance = "high";
    tags.push("decision");
  } else if (hasAction) {
    category = "action";
    importance = "high";
    tags.push("action");
  } else if (hasPreference) {
    category = "preference";
    importance = "medium";
    tags.push("preference");
  }

  // Long conversations are more likely to contain important context
  if (content.length > 3000 && importance === "medium") {
    importance = "high";
  }

  return { category, importance, tags };
}

export default saveSessionToMemory;
