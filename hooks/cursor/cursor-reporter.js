#!/usr/bin/env node
// Spaces agent reporter for Cursor.
//
// Tells the Spaces bar widget what this Cursor agent session is doing, so a
// Cursor window (or a terminal running cursor-agent) gets the same badge a
// Claude Code terminal gets.
//
//   working  the agent is running
//   done     the agent finished its turn
//   end      the conversation is gone
//
// Reports go out through the same omarchy-shell entry point the Claude Code
// hook uses, so the widget side needs no Cursor-specific code:
//
//   omarchy-shell tornikegomareli.spaces agent <session> <state> <pids>
//
// The pid list is this process and its ancestors; the widget matches them
// against windows to find which one to badge. For the desktop app that walks
// back to the Cursor window; for cursor-agent in a terminal, to that terminal.
//
// Register in ~/.cursor/hooks.json (covers both the IDE and cursor-agent):
//
//   {
//     "version": 1,
//     "hooks": {
//       "beforeSubmitPrompt":   [{ "command": "cursor-spaces-hook", "timeout": 10 }],
//       "sessionStart":         [{ "command": "cursor-spaces-hook", "timeout": 10 }],
//       "preToolUse":           [{ "command": "cursor-spaces-hook", "timeout": 10 }],
//       "beforeShellExecution": [{ "command": "cursor-spaces-hook", "timeout": 10 }],
//       "afterShellExecution":  [{ "command": "cursor-spaces-hook", "timeout": 10 }],
//       "afterFileEdit":        [{ "command": "cursor-spaces-hook", "timeout": 10 }],
//       "postToolUse":          [{ "command": "cursor-spaces-hook", "timeout": 10 }],
//       "afterAgentThought":    [{ "command": "cursor-spaces-hook", "timeout": 10 }],
//       "stop":                 [{ "command": "cursor-spaces-hook", "timeout": 10, "loop_limit": null }],
//       "sessionEnd":           [{ "command": "cursor-spaces-hook", "timeout": 10 }]
//     }
//   }
//
// The stop entry needs "loop_limit": null: Cursor disables stop hooks after 5
// runs by default, which would silently kill the reporter mid-session.
//
// State decisions live in cursor-state.js, which is pure and unit tested.

import { spawnSync } from "node:child_process"
import { mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { hasPendingTurn, sessionKey, stateForEvent, trackedId } from "./cursor-state.js"

const PLUGIN_ID = "tornikegomareli.spaces"

function parentPid(pid) {
  // /proc/<pid>/stat field 4 is ppid, but the comm field can contain spaces
  // and parens, so cut everything up to the closing paren first.
  // (Same walk as the opencode reporter: the tree shape is what matters.)
  try {
    const stat = readFileSync(`/proc/${pid}/stat`, "utf8")
    const rest = stat.slice(stat.lastIndexOf(")") + 1).trim()
    return Number(rest.split(" ")[1]) || 0
  } catch {
    return 0
  }
}

// This process plus every ancestor, so the widget can walk back to the
// Cursor window or terminal that owns us.
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

// Synchronous: this process exits as soon as stdin ends, so an async spawn
// might never flush. Failures here are not the agent's problem.
function send(session, state, pids) {
  if (!session || !state) return
  try {
    spawnSync("omarchy-shell", [PLUGIN_ID, "agent", String(session), state, pids.join(",")], {
      stdio: "ignore",
    })
  } catch {}
}

// Per-session turn ledger, so a stop only reports done when no submitted
// turn is still unstopped (queued prompts start silently). One empty file
// per turn id under submitted/ or stopped/: creating a file is atomic, so
// concurrent hook runs cannot lose an update the way read-modify-write of a
// single JSON file could. Returns true when a turn is still pending.
function sessionDir(session) {
  const safe = String(session || "unknown").replace(/[^a-zA-Z0-9_-]/g, "_")
  return join(tmpdir(), "cursor-spaces", safe)
}

function listIds(dir) {
  try {
    return readdirSync(dir)
  } catch {
    return []
  }
}

function trackTurn(session, turn, id) {
  if (!id) return false
  try {
    const dir = join(sessionDir(session), turn)
    mkdirSync(dir, { recursive: true })
    writeFileSync(join(dir, id.replace(/[^a-zA-Z0-9_-]/g, "_")), "")
    sweepSessions()
    const base = sessionDir(session)
    return hasPendingTurn(listIds(join(base, "submitted")), listIds(join(base, "stopped")))
  } catch {
    return false
  }
}

function forgetSession(session) {
  try {
    rmSync(sessionDir(session), { recursive: true, force: true })
  } catch {}
}

// Sessions whose agent died mid-queue never send sessionEnd; drop ledgers
// older than a day so they do not accumulate in tmp.
function sweepSessions() {
  try {
    const root = join(tmpdir(), "cursor-spaces")
    const cutoff = Date.now() - 24 * 60 * 60 * 1000
    for (const entry of listIds(root)) {
      const dir = join(root, entry)
      try {
        if (statSync(dir).mtimeMs < cutoff) rmSync(dir, { recursive: true, force: true })
      } catch {}
    }
  } catch {}
}

function main() {
  let raw = ""
  try {
    raw = readFileSync(0, "utf8")
  } catch {}
  // Observational hook: never block the agent loop, whatever stdin holds.
  let payload
  try {
    payload = JSON.parse(raw)
  } catch {
    payload = {}
  }
  const event = payload.hook_event_name || payload.hook_event || payload.event || ""
  const state = stateForEvent(event)
  if (!state) return
  const session = sessionKey(payload)
  if (event === "sessionEnd") {
    forgetSession(session)
    send(session, state, pidChain())
    return
  }
  if (event === "beforeSubmitPrompt" || event === "stop") {
    const turn = state === "done" ? "stopped" : "submitted"
    if (trackTurn(session, turn, trackedId(payload)) && state === "done") {
      // A queued follow-up is still unstopped: its start emits nothing, so
      // reporting done now would stick until late in that turn. Hold.
      return
    }
  }
  send(session, state, pidChain())
}

main()
// Cursor ignores stdout on observational hooks; an empty object keeps the
// contract explicit on the off chance it ever looks.
process.stdout.write("{}\n")
