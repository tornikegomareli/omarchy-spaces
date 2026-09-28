// Pure mapping for the Cursor agent reporter (see cursor-reporter.js).
//
// No IO, no Cursor imports: the reporter reads one hook event from stdin,
// and this file decides which Spaces state that event means, if any.
// Exercised by node (see tests/cursor-reporter.test.js).
//
// Cursor spawns a fresh process per hook event, so there is no cross-event
// memory here. Each event maps to at most one report:
//
//   "working"  the agent started or kept working:
//              beforeSubmitPrompt, sessionStart, preToolUse,
//              beforeShellExecution, afterAgentThought
//   "done"     the turn reached a completion point: stop
//              (any status: completed, aborted, error). An aborted turn still
//              deserves a look, and the next prompt flips back to working.
//   "end"      the conversation closed: sessionEnd
//
// Deliberately absent: "waiting". Cursor exposes no hook for "the agent
// asked the user a question", so a waiting badge would be a guess. Also
// silent: afterAgentResponse (fires mid-turn before tool calls, so reporting
// done there would strobe every turn), postToolUseFailure, preCompact,
// subagents, and Tab hooks.
//
// Queued prompts need more than the map above. Each submitted prompt carries
// its own generation_id, and a queued follow-up starts with no event at all:
// its beforeSubmitPrompt already fired while the previous turn was running.
// So "stop" only means "done" when every submitted generation has stopped.
// The reporter persists the two id sets per session (one file per id, so
// concurrent hook runs cannot lose an update) and asks hasPendingTurn
// before reporting done:

// trackedId returns the turn id carried by submit/stop events, or "" when
// the payload has none (older payloads, mid-session installs).
export function trackedId(payload = {}) {
  return payload.generation_id || ""
}

// hasPendingTurn is true while a submitted turn has no matching stop.
// A stop for an untracked turn (hook installed mid-session) leaves no
// pending turn, so it still reports done exactly once.
export function hasPendingTurn(submitted, stopped) {
  const done = new Set(stopped)
  return submitted.some((id) => !done.has(id))
}

// Events that mean the agent is (still) working.
const WORKING = new Set([
  "beforeSubmitPrompt",
  "sessionStart",
  "preToolUse",
  "beforeShellExecution",
  "afterAgentThought",
  // Tool completions also mean working. cursor-agent in a terminal never
  // fires beforeSubmitPrompt for queued follow-ups, so without these the
  // badge sits on done until late in the next turn, then flickers
  // working -> done. Any tool activity restarts the working signal instead.
  "postToolUse",
  "afterShellExecution",
  "afterFileEdit",
])

// stateForEvent returns "working", "done", "end", or "" to stay silent.
export function stateForEvent(eventName) {
  if (!eventName) return ""
  if (WORKING.has(eventName)) return "working"
  if (eventName === "stop") return "done"
  if (eventName === "sessionEnd") return "end"
  return ""
}

// sessionKey returns a stable id for the conversation the event belongs to,
// so the widget badges one entry per chat. conversation_id and session_id
// are the same identifier; transcript_path is per-conversation, so it works
// as a fallback where the ids are missing.
export function sessionKey(payload = {}) {
  return (
    payload.conversation_id ||
    payload.session_id ||
    payload.transcript_path ||
    (Array.isArray(payload.workspace_roots) ? payload.workspace_roots[0] : "") ||
    ""
  )
}
