// Run: node tests/opencode-report.test.js
//
// Shape checks for the opencode reporters themselves. The state machine under
// them is tested in tests/opencode-plugin.test.js; this file checks that every
// entrypoint still exists with the shape its runtime expects, and that a v2
// setup() call wires nothing up (it must stay silent so the TUI reporter owns
// the badge).
const path = require("path")
const assert = require("assert")
const { pathToFileURL } = require("url")

const hooks = path.join(__dirname, "..", "hooks")

let failed = 0
async function test(name, fn) {
  try {
    await fn()
    console.log("ok   " + name)
  } catch (e) {
    failed++
    console.log("FAIL " + name + "\n     " + e.message)
  }
}

async function main() {
  const serverMod = await import(pathToFileURL(path.join(hooks, "opencode-plugin.js")).href)
  const tuiMod = await import(pathToFileURL(path.join(hooks, "opencode-tui.js")).href)
  const server = serverMod.default

  await test("the server plugin keeps the v2 default export shape", () => {
    assert.strictEqual(typeof server, "object", "default export must be an object")
    assert.strictEqual(server.id, "tornikegomareli.spaces")
    assert.strictEqual(typeof server.setup, "function")
    assert.strictEqual(typeof server.server, "function")
  })

  await test("the v1 named export still produces hooks", async () => {
    assert.strictEqual(typeof serverMod.SpacesAgent, "function")
    const hooks = await serverMod.SpacesAgent()
    for (const name of ["event", "chat.message", "tool.execute.after", "permission.ask", "dispose"]) {
      assert.strictEqual(typeof hooks[name], "function", `hook ${name} missing`)
    }
    await hooks.dispose()
  })

  await test("the v1 server() object entrypoint returns the same hooks", async () => {
    const hooks = await server.server()
    for (const name of ["event", "chat.message", "tool.execute.after", "permission.ask", "dispose"]) {
      assert.strictEqual(typeof hooks[name], "function", `hook ${name} missing`)
    }
    await hooks.dispose()
  })

  await test("the v2 setup() wires nothing up", async () => {
    // The TUI companion must stay the only reporter on v2: a server-side
    // report can never match a window, and a late one erases the badge.
    assert.strictEqual(await server.setup(), undefined)
  })

  await test("the v1 event hook swallows malformed events", async () => {
    const hooks = await serverMod.SpacesAgent()
    for (const event of [undefined, {}, { type: "mystery" }, { type: "session.idle" }]) {
      await hooks.event({ event })
    }
    await hooks.dispose()
  })

  await test("the TUI companion advertises its own id and setup", () => {
    assert.strictEqual(tuiMod.default.id, "tornikegomareli.spaces.tui")
    assert.strictEqual(typeof tuiMod.default.setup, "function")
  })

  await test("the TUI companion ignores missing event channels", async () => {
    const cleanup = await tuiMod.default.setup({})
    await cleanup()
  })

  await test("the TUI companion only reports for sessions it shows", async () => {
    const seen = []
    const cleanup = await tuiMod.default.setup(
      {
        ui: {
          router: { current: () => ({ type: "session", sessionID: "s1" }) },
          tabs: { list: () => [{ sessionID: "s1" }] },
        },
        data: {
          session: { root: (id) => id },
          listen: (cb) => {
            cb({ details: { type: "session.step.started", data: { sessionID: "s1" } } })
            cb({ details: { type: "session.step.started", data: { sessionID: "foreign" } } })
            return () => {}
          },
        },
      },
      { send: (session, state) => seen.push(`${session}=${state}`) },
    )
    await cleanup()
    assert.deepStrictEqual(seen, ["s1=working", "s1=end"])
  })

  await test("subagent sessions are reported under their root", async () => {
    const seen = []
    const cleanup = await tuiMod.default.setup(
      {
        ui: {
          router: { current: () => ({ type: "session", sessionID: "s1" }) },
          tabs: { list: () => [] },
        },
        data: {
          session: {
            root: (id) => (id.startsWith("sub") ? "s1" : id),
          },
          listen: (cb) => {
            cb({ details: { type: "session.tool.called", data: { sessionID: "sub-agent" } } })
            return () => {}
          },
        },
      },
      { send: (session, state) => seen.push(`${session}=${state}`) },
    )
    await cleanup()
    assert.deepStrictEqual(seen, ["s1=working", "s1=end"])
  })

  await test("a claimed session stays claimed after navigating away", async () => {
    const seen = []
    let route = { type: "session", sessionID: "s1" }
    const cleanup = await tuiMod.default.setup(
      {
        ui: {
          router: { current: () => route },
          tabs: { list: () => [] },
        },
        data: {
          session: { root: (id) => id },
          listen: (cb) => {
            cb({ details: { type: "session.step.started", data: { sessionID: "s1" } } })
            route = { type: "home" }
            cb({ details: { type: "session.tool.called", data: { sessionID: "s1" } } })
            cb({ details: { type: "session.step.ended", data: { sessionID: "s1" } } })
            return () => {}
          },
        },
      },
      { send: (session, state) => seen.push(`${session}=${state}`) },
    )
    await cleanup()
    assert.deepStrictEqual(seen, ["s1=working", "s1=end"])
  })

  await test("outside a TUI the reporter is unscoped (opencode run)", async () => {
    const seen = []
    let feed
    const cleanup = await tuiMod.default.setup(
      {
        data: {
          listen: (cb) => {
            feed = cb
            return () => {}
          },
        },
      },
      { send: (session, state) => seen.push(`${session}=${state}`) },
    )
    feed({ details: { type: "session.step.started", data: { sessionID: "any-run" } } })
    await cleanup()
    assert.deepStrictEqual(seen, ["any-run=working", "any-run=end"])
  })

  process.exit(failed ? 1 : 0)
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
