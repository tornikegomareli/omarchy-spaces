// Spaces agent reporter for opencode (TUI side).
//
// Why this file exists: server plugins run in the shared background service
// (`opencode serve --service`, a child of systemd), so their pid chain never
// contains the terminal window. The Spaces widget badges a window by matching
// the reported pids against terminal windows, so server-side reports can't
// pin a badge. This TUI plugin runs in the terminal's own opencode client
// process, whose pid chain walks back to the terminal window that owns us.
//
// It reports through the same omarchy-shell entry point as every other agent:
//
//   omarchy-shell tornikegomareli.spaces agent <session> <state> <pids>
//
// State decisions live in opencode-state.js, which is pure and unit tested.
//
// Install as a CLI-only plugin so it stays active against the shared
// background service (server plugins run there and cannot see the terminal):
//
//   mkdir -p ~/.config/opencode/plugins/spaces-tui
//   ln -sfn ~/.config/omarchy/plugins/tornikegomareli.spaces/hooks/opencode-tui.js \
//           ~/.config/opencode/plugins/spaces-tui/tui.js
//
// and add the directory to ~/.config/opencode/cli.json:
//
//   { "plugins": ["~/.config/opencode/plugins/spaces-tui"] }
//
// (Use $HOME instead of ~ if OpenCode does not expand it.) On OpenCode v2
// this file does the reporting and the server plugin (opencode-plugin.js)
// stays silent, so this link is the only one v2 needs. On OpenCode 1.x, which
// runs plugins inside the terminal itself, the server plugin reports instead.
// Restart the OpenCode TUI, run a prompt, and the terminal badges while it
// works.

import { spawn } from "node:child_process"
import { readFileSync } from "node:fs"
import { WAIT_DELAY, needsWaitTimer, reduce } from "./opencode-state.js"

const PLUGIN_ID = "tornikegomareli.spaces"
// Idle events don't reach every session kind; when they don't, a quiet
// period after the last step end stands in for turn end.
const DONE_DELAY = 3000

function parentPid(pid) {
  try {
    const stat = readFileSync(`/proc/${pid}/stat`, "utf8")
    const rest = stat.slice(stat.lastIndexOf(")") + 1).trim()
    return Number(rest.split(" ")[1]) || 0
  } catch {
    return 0
  }
}

// This process (the terminal's opencode client) plus every ancestor, so the
// widget can walk back to the terminal window that owns us.
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
    const child = spawn("omarchy-shell", [PLUGIN_ID, "agent", String(session), state, pids.join(",")], {
      detached: true,
      stdio: "ignore",
    })
    child.on("error", () => {})
    child.unref()
  } catch {}
}

function createReporter(options = {}) {
  const pids = pidChain()
  const deliver = options.deliver || send
  // Optional ownership scope: maps a session to its owning session id (the
  // TUI-displayed root), or to undefined for foreign sessions.
  const canonical = options.canonical
  const sessions = new Map()
  const timers = new Map()
  // Fallback done timers: some sessions (e.g. API-driven ones) never emit
  // session.idle, only step/tool/text events. A step end with no follow-up
  // step within DONE_DELAY means the turn is over; a new step cancels it.
  const doneTimers = new Map()
  const permIds = new Map()
  const permBare = new Map()

  function forgetPermission(session) {
    permIds.delete(session)
    permBare.delete(session)
  }

  function cancelDoneTimer(session) {
    const timer = doneTimers.get(session)
    if (timer) {
      clearTimeout(timer)
      doneTimers.delete(session)
    }
  }

  function armDoneTimer(session) {
    cancelDoneTimer(session)
    doneTimers.set(
      session,
      setTimeout(() => {
        doneTimers.delete(session)
        apply(session, "idle")
      }, DONE_DELAY),
    )
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
    // Any real work cancels a pending fallback done.
    if (signal === "prompt" || signal === "tool" || signal === "busy" || signal === "permission") {
      cancelDoneTimer(session)
    }
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

    if (next.emit) {
      deliver(session, next.emit, pids)
    }
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

  // V2 TUI events carry the payload in `data` ({details} from data.listen).
  function normalize(type, properties = {}) {
    let session = properties.sessionID
    if (!session) return
    if (canonical) {
      const owner = canonical(session)
      if (!owner) return
      session = owner
    }
    switch (type) {
      case "permission.asked":
        notePermission(session, properties.id)
        break
      case "permission.replied":
        noteReplied(session, properties.requestID)
        break
      case "session.status":
        if (properties.status && properties.status.type !== "idle") apply(session, "busy")
        break
      case "session.idle":
        cancelDoneTimer(session)
        apply(session, "idle")
        break
      case "session.deleted":
        cancel(session)
        cancelDoneTimer(session)
        forgetPermission(session)
        sessions.delete(session)
        deliver(session, "end", pids)
        break
      // Working signals: a new turn starting or progressing. Duplicates are
      // deduped by the state machine, so over-mapping is safe. Turn end is
      // session.idle when emitted; step.ended arms a fallback (see below)
      // because some sessions never emit idle.
      case "session.inbox.delivered":
      case "session.inbox.enqueued":
        apply(session, "prompt")
        break
      case "session.execution.started":
      case "session.step.started":
        apply(session, "busy")
        break
      case "session.tool.called":
      case "session.tool.success":
      case "session.tool.failed":
        apply(session, "tool")
        break
      case "session.step.ended":
        // Fallback turn-end: a new step arriving first cancels this (the
        // turn continues). Real session.idle, when emitted, wins earlier.
        armDoneTimer(session)
        break
    }
  }

  function normalizeEvent(event) {
    if (!event) return
    try {
      normalize(event.type, event.data ?? event.properties ?? {})
    } catch {}
  }

  function dispose() {
    for (const [session] of sessions) {
      cancel(session)
      cancelDoneTimer(session)
      forgetPermission(session)
      deliver(session, "end", pids)
    }
    sessions.clear()
  }

  return { pids, apply, normalize, normalizeEvent, dispose }
}

// Ownership scope: which sessions belong to this TUI. Every open TUI client
// receives the full event stream, so an unscoped reporter would claim every
// session from all of them - and each reporter's pid chain pins its own
// terminal, so the widget's window for the session would flip between the
// competing reporters, frequently hiding the badge. Scoping uses what the
// TUI shows (the current route plus any open session tabs) and maps foreign
// sessions, including subagents, back to their root. Outside a TUI
// (headless `opencode run`, which has no owner) nothing is scoped, because
// the run's pid chain still reaches its terminal.
function ownership(context) {
  // Sticky: sessions this TUI has ever shown. If the user navigates to the
  // home screen (or another tab) while an agent runs, live routes and tabs
  // stop listing the session, and a purely live scope would drop its signals
  // and freeze the badge on "working". A session is released by
  // session.deleted or when the TUI unloads, not by navigation.
  const owned = new Set()
  const scan = () => {
    try {
      const ui = context && context.ui
      const route = ui?.router?.current?.()
      if (route && route.type === "session" && route.sessionID) owned.add(route.sessionID)
      for (const tab of ui?.tabs?.list?.() ?? []) {
        if (tab && tab.sessionID) owned.add(tab.sessionID)
      }
    } catch {}
  }
  const isShown = () => {
    const ui = context && context.ui
    return (
      typeof ui?.router?.current === "function" || typeof ui?.tabs?.list === "function"
    )
  }
  if (!isShown()) return undefined
  if (!owned.size) scan()
  return (sessionID) => {
    scan()
    if (owned.has(sessionID)) return sessionID
    try {
      const root = context?.data?.session?.root?.(sessionID)
      return typeof root === "string" && root && owned.has(root) ? root : undefined
    } catch {
      return undefined
    }
  }
}

// CLI/TUI entrypoint: plain object, no @opencode/plugin dependency.
export default {
  id: `${PLUGIN_ID}.tui`,

  // `internal` is for tests only: it overrides how reports leave the process,
  // so tests can collect reports without spawning omarchy-shell.
  setup(context, internal = {}) {
    const canonical = ownership(context)
    const reporter = createReporter({
      canonical,
      deliver: internal.send,
    })

    // Every server event, including session/permission updates.
    const stop =
      context && context.data && typeof context.data.listen === "function"
        ? context.data.listen(({ details }) => reporter.normalizeEvent(details))
        : () => {}

    const onExit = () => {
      reporter.dispose()
    }
    process.once("exit", onExit)

    return () => {
      try {
        stop()
      } catch {}
      process.removeListener("exit", onExit)
      reporter.dispose()
    }
  },
}
