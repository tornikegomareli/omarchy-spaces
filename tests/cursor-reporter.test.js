// Run: node tests/cursor-reporter.test.js
//
// The mapping in hooks/cursor/cursor-state.js decides what the Spaces bar
// shows for each Cursor hook event. It is pure, so it is tested here with no
// Cursor and no processes.
const path = require("path")
const assert = require("assert")
const { pathToFileURL } = require("url")

let failed = 0
function test(name, fn) {
  try {
    fn()
    console.log("ok   " + name)
  } catch (e) {
    failed++
    console.log("FAIL " + name + "\n     " + e.message)
  }
}

function main() {
  const file = pathToFileURL(path.join(__dirname, "..", "hooks", "cursor", "cursor-state.js")).href
  return import(file).then((M) => {
    test("work events report working", () => {
      for (const event of [
        "beforeSubmitPrompt",
        "sessionStart",
        "preToolUse",
        "beforeShellExecution",
        "afterAgentThought",
      ]) {
        assert.strictEqual(M.stateForEvent(event), "working", event)
      }
    })

    test("tool completions report working for queued CLI turns", () => {
      // cursor-agent never fires beforeSubmitPrompt for a queued follow-up:
      // the first sign of the next turn is a tool finishing.
      for (const event of ["postToolUse", "afterShellExecution", "afterFileEdit"]) {
        assert.strictEqual(M.stateForEvent(event), "working", event)
      }
    })

    test("stop reports done whatever the status", () => {
      // The payload status (completed/aborted/error) does not change the
      // badge: only the event name matters.
      assert.strictEqual(M.stateForEvent("stop"), "done")
    })

    test("sessionEnd reports end", () => {
      assert.strictEqual(M.stateForEvent("sessionEnd"), "end")
    })

    test("mid-turn and observer events stay silent", () => {
      // afterAgentResponse fires before tool calls, so reporting done there
      // would strobe the badge every turn.
      for (const event of [
        "afterAgentResponse",
        "postToolUseFailure",
        "preCompact",
        "subagentStart",
        "subagentStop",
        "beforeSubmitPrompt2",
        "",
        undefined,
      ]) {
        assert.strictEqual(M.stateForEvent(event), "", String(event))
      }
    })

    test("session key prefers conversation_id", () => {
      assert.strictEqual(
        M.sessionKey({ conversation_id: "conv", session_id: "sess" }),
        "conv",
      )
    })

    test("session key falls back to session_id then transcript", () => {
      assert.strictEqual(M.sessionKey({ session_id: "sess" }), "sess")
      assert.strictEqual(M.sessionKey({ transcript_path: "/tmp/t.json" }), "/tmp/t.json")
    })

    test("session key falls back to the first workspace root", () => {
      assert.strictEqual(M.sessionKey({ workspace_roots: ["/repo", "/other"] }), "/repo")
    })

    test("session key is empty when nothing identifies the chat", () => {
      assert.strictEqual(M.sessionKey({}), "")
      assert.strictEqual(M.sessionKey(), "")
    })

    test("tracked id is the generation id", () => {
      assert.strictEqual(M.trackedId({ generation_id: "g1" }), "g1")
      assert.strictEqual(M.trackedId({}), "")
      assert.strictEqual(M.trackedId(), "")
    })

    test("a stop with nothing pending leaves no pending turn", () => {
      assert.strictEqual(M.hasPendingTurn([], []), false)
      assert.strictEqual(M.hasPendingTurn([], ["g1"]), false)
      assert.strictEqual(M.hasPendingTurn(["g1"], ["g1"]), false)
    })

    test("an unstopped submit is a pending turn", () => {
      // Two queued prompts, first turn stopped: the follow-up starts with
      // no event, so done must wait for its stop.
      assert.strictEqual(M.hasPendingTurn(["g1", "g2"], ["g1"]), true)
      assert.strictEqual(M.hasPendingTurn(["g1", "g2"], ["g1", "g2"]), false)
    })

    if (failed) {
      console.log(failed + " FAILURES")
      process.exit(1)
    }
    console.log("all cursor reporter tests pass")
  })
}

main().catch((e) => {
  console.log("FAIL harness\n     " + e.message)
  process.exit(1)
})
