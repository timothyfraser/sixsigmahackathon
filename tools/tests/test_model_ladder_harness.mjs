// Drives the real plugin entry point with a fake OpenCode ctx and one error event.
// Usage: node tools/tests/test_model_ladder_harness.mjs <dir> <json-event-data>
import { pathToFileURL } from "node:url";
import { join, resolve } from "node:path";
const [dir, payload] = process.argv.slice(2);
const plugin = (await import(pathToFileURL(resolve(".opencode/plugins/model-ladder.js")).href)).default;
const calls = [];
const event = { type: "session.error", data: JSON.parse(payload) };
const ctx = {
  location: { directory: dir },
  session: {
    get: async () => ({ model: { providerID: "google", id: "gemini-3.1-flash-lite" } }),
    switchModel: async (a) => calls.push({ switchModel: a }),
    synthetic: async (a) => calls.push({ synthetic: a }),
  },
  event: { subscribe: async function* () { yield event; } },
};
await plugin.setup(ctx);
await new Promise((r) => setTimeout(r, 300));
console.log(JSON.stringify({ id: plugin.id, calls }));
