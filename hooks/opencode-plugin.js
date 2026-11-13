// Spaces agent reporter for opencode.
//
// Tells the Spaces bar widget what this opencode session is doing, so a terminal
// running opencode gets the same badge a Claude Code terminal gets.
//
//   working  the agent is running
//   waiting  the agent needs an answer
//   done     the agent finished its turn
//   end      the session is gone
//
// Reports go out through the same omarchy-shell entry point the Claude Code
// hook uses, so the widget side needs no opencode-specific code:
//
//   omarchy-shell tornikegomareli.spaces agent <session> <state> <pids>
//
// The pid list is this process and its ancestors; the widget matches them
// against terminal windows to find which one to badge.
//
// Install (OpenCode 1.x only; see below) by linking the installed plugin's
// copy into OpenCode, so `omarchy plugin update` keeps the reporter current:
//
//   ln -sfn ~/.config/omarchy/plugins/tornikegomareli.spaces/hooks/opencode-plugin.js \
//           ~/.config/opencode/plugins/spaces.js
//
// State decisions live in opencode-state.js, which is pure and unit tested.
//
// Whether this file reports depends on the opencode version. OpenCode 1.x
// runs plugins inside the terminal's own opencode process, so the pid chain
// here reaches the terminal window and reporting works as-is: through the
// `SpacesAgent` named export on any 1.x, and through the default export's
// `server()` object entrypoint (documented from 1.18.29; the loaders back to
// 1.14 reach it the same way). OpenCode v2 runs server plugins in its shared
// background service instead, where the pid chain can never match a window,
// so `setup()` stays silent here and the TUI companion hooks/opencode-tui.js
// does the reporting from the terminal side.

import { spawn, spawnSync } from "node:child_process"
import { readFileSync } from "node:fs"
import { WAIT_DELAY, needsWaitTimer, reduce } from "./opencode-state.js"

const PLUGIN_ID = "tornikegomareli.spaces"

function parentPid(pid) {
  // /proc/<pid>/stat field 4 is ppid, but the comm field can contain spaces
  // and parens, so cut everything up to the closing paren first.
  try {
    const stat = readFileSync(`/proc/${pid}/stat`, "utf8")
    const rest = stat.slice(stat.lastIndexOf(")") + 1).trim()
    return Number(rest.split(" ")[1]) || 0
  } catch {
    return 0
  }
}

// This process plus every ancestor, so the widget can walk back to the
// terminal window that owns us. Cached: the tree does not change under us.
function pidChain(pid = process.pid) {
  const chain = []
  let current = pid
  while (current > 1) {
    chain.push(current)
    const next = parentPid(current)
    if (!next || next === current) break
    current = next
  }
  return chain
}

function send(session, state, pids) {
  if (!session || !state) return
  try {
    // Detached and unref'd: the agent never waits on the bar, and the bar
    // never waits on the agent. Failures here are not the agent's problem.
    const child = spawn("omarchy-shell", [PLUGIN_ID, "agent", String(session), state, pids.join(",")], {
      detached: true,
      stdio: "ignore",
    })
    child.on("error", () => {})
    child.unref()
  } catch {}
}

// Synchronous twin for the exit handler: async work never flushes after
// "exit", so the last "end" report must block.
function sendSync(session, state, pids) {
  if (!session || !state) return
  try {
    spawnSync("omarchy-shell", [PLUGIN_ID, "agent", String(session), state, pids.join(",")], {
      stdio: "ignore",
    })
  } catch {}
}

// Shared reporter core: per-session state machine plus the pid list.
// V1 (`SpacesAgent`) and V2 (`setup`) are thin adapters over this.
function createReporter() {
  const pids = pidChain()
  const sessions = new Map()
  const timers = new Map()
  // Seen permission request ids per session, and id-less hook reports still
  // waiting for their event twin. opencode reports each permission twice:
  // the `permission.ask` hook fires first, then the `permission.asked` event
  // for the same request. Counting both would need two replies for one
  // prompt and wedge the badge on "waiting".
  const permIds = new Map()
  const permBare = new Map()

  function forgetPermission(session) {
    permIds.delete(session)
    permBare.delete(session)
  }

  function cancel(session) {
    const timer = timers.get(session)
    if (timer) {
      clearTimeout(timer)
      timers.delete(session)
    }
  }

  function apply(session, signal) {
    if (!session) return
    const next = reduce(sessions.get(session), signal)
    sessions.set(session, next)

    if (needsWaitTimer(next)) {
      if (!timers.has(session)) {
        timers.set(
          session,
          setTimeout(() => {
            timers.delete(session)
            apply(session, "timer")
          }, WAIT_DELAY),
        )
      }
    } else {
      cancel(session)
    }

    if (next.emit) send(session, next.emit, pids)
  }

  function notePermission(session, id) {
    if (id == null) {
      permBare.set(session, (permBare.get(session) || 0) + 1)
      apply(session, "permission")
      return
    }
    let ids = permIds.get(session)
    if (!ids) {
      ids = new Set()
      permIds.set(session, ids)
    }
    if (ids.has(id)) return
    ids.add(id)
    const bare = permBare.get(session) || 0
    if (bare > 0) {
      // The id-less hook report just before this event was the same request:
      // adopt its pending count instead of counting a second prompt.
      if (bare === 1) permBare.delete(session)
      else permBare.set(session, bare - 1)
      return
    }
    apply(session, "permission")
  }

  function noteReplied(session, id) {
    if (id != null) {
      const ids = permIds.get(session)
      if (ids) {
        ids.delete(id)
        if (!ids.size) permIds.delete(session)
      }
    } else {
      const bare = (permBare.get(session) || 0) - 1
      if (bare <= 0) permBare.delete(session)
      else permBare.set(session, bare)
    }
    apply(session, "replied")
  }

  function normalize(type, properties = {}) {
    const session = properties.sessionID
    if (!session) return
    switch (type) {
      case "permission.updated":
      case "permission.asked":
      case "permission.v2.asked":
        notePermission(session, properties.id)
        break
      case "permission.replied":
      case "permission.v2.replied":
        noteReplied(session, properties.requestID)
        break
      case "session.status":
        if (properties.status && properties.status.type !== "idle") apply(session, "busy")
        break
      case "session.idle":
        apply(session, "idle")
        break
      case "session.deleted":
        cancel(session)
        forgetPermission(session)
        sessions.delete(session)
        send(session, "end", pids)
        break
    }
  }

  // V2 events carry the payload in `data`; V1 used `properties`.
  function normalizeEvent(event) {
    if (!event) return
    try {
      normalize(event.type, event.data ?? event.properties ?? {})
    } catch {}
  }

  function sendAllEndSync() {
    for (const [session] of sessions) {
      cancel(session)
      sendSync(session, "end", pids)
    }
  }

  function dispose() {
    for (const [session] of sessions) {
      cancel(session)
      forgetPermission(session)
      send(session, "end", pids)
    }
    sessions.clear()
  }

  return { pids, apply, notePermission, noteReplied, normalize, normalizeEvent, sendAllEndSync, dispose }
}

export const SpacesAgent = async () => {
  const reporter = createReporter()

  // dispose covers a normal quit. This is the net for a hard exit, where the
  // bar would otherwise keep a stale "working" badge on a dead window.
  // Synchronous: async spawns never flush inside an exit handler.
  process.once("exit", () => {
    reporter.sendAllEndSync()
  })

  return {
    event: async ({ event } = {}) => {
      if (!event) return
      reporter.normalizeEvent(event)
    },

    "chat.message": async (input) => {
      reporter.apply(input && input.sessionID, "prompt")
    },

    "tool.execute.after": async (input) => {
      reporter.apply(input && input.sessionID, "tool")
    },

    "permission.ask": async (input, output) => {
      if (output && output.status !== "ask") return
      // input.id is optional in older opencode; without it the request still
      // counts, and its event twin adopts the count when it arrives with one.
      reporter.notePermission(input && input.sessionID, input && input.id)
    },

    dispose: async () => {
      reporter.dispose()
    },
  }
}

// OpenCode V2 entrypoint. Plain object (no @opencode/plugin import) so the
// plugin has no new runtime dependency. V2 requires the default export to
// exist, but it must report nothing: v2 runs server plugins in the shared
// background service, whose process tree is not under the terminal, and the
// bar keeps a badge only while the latest report's pid chain matches a
// window. Reporting from here would unbadge the terminal whenever a service
// report landed after the TUI reporter's, so on v2 the TUI companion
// (hooks/opencode-tui.js) is the only reporter.
export default {
  id: PLUGIN_ID,

  async setup() {},

  // OpenCode V1 object entrypoint (documented from 1.18.29; the loaders
  // reach it the same way back to 1.4): same hooks as SpacesAgent.
  async server() {
    return SpacesAgent()
  },
}
