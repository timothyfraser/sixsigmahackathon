// Model ladder: when a free Gemini model hits its DAILY limit, switch to the next
// model on the ladder and carry on. Edit the ladder in model-ladder.lib.mjs.
// Per-minute limits and "high demand" (503) errors are left to OpenCode's own retry.
import { readFileSync, writeFileSync, appendFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import {
  LADDER, classify, modelFromError, nextModel, firstLive, exhaustedNow,
  expiryFor, markInState, switchedLine, END_OF_LADDER, splitRef,
} from "./model-ladder.lib.mjs";

export default {
  id: "model-ladder",
  async setup(ctx) {
    const dir = join(ctx?.location?.directory ?? process.cwd(), ".opencode");
    const stateFile = join(dir, "model-ladder-state.json");
    const debug = process.env.MODEL_LADDER_DEBUG === "1";
    const log = (msg) => {
      if (!debug) return;
      try { appendFileSync(join(tmpdir(), "model-ladder-debug.log"), `${new Date().toISOString()} ${msg}\n`); } catch {}
    };
    const load = () => { try { return JSON.parse(readFileSync(stateFile, "utf8")); } catch { return null; } };
    // Used-up models come back when Google says they do (the error's retry time),
    // never later than midnight Pacific.
    const markExhausted = (ref, err) => {
      const until = expiryFor(err);
      const state = markInState(load(), ref, until);
      try {
        mkdirSync(dir, { recursive: true });
        writeFileSync(stateFile, JSON.stringify(state, null, 2));
      } catch (e) { log(`state write failed: ${e}`); }
      log(`exhausted ${ref} until ${until.toISOString()}`);
      return { dead: exhaustedNow(state), until };
    };
    const handled = new Map(); // "session|model" -> time (ms) the model comes back
    log(`loaded; ladder=${LADDER.join(",")}`);

    async function currentModel(sessionID, err) {
      const named = modelFromError(err);
      if (named) return named;
      try {
        const s = await ctx.session.get({ sessionID });
        const m = s?.model ?? s?.info?.model;
        if (m) return `${m.providerID}/${m.id ?? m.modelID ?? m.model}`;
      } catch {}
      return null;
    }

    async function onError(sessionID, err, type) {
      const kind = classify(err);
      log(`event ${type} session=${sessionID} kind=${kind}`);
      if (kind !== "daily" || !sessionID) return;
      const from = await currentModel(sessionID, err);
      const key = `${sessionID}|${from}`;
      if ((handled.get(key) ?? 0) > Date.now()) return;
      let dead;
      if (from) {
        const r = markExhausted(from, err);
        dead = r.dead;
        handled.set(key, r.until.getTime());
      } else {
        dead = exhaustedNow(load());
      }
      const to = nextModel(from, dead);
      if (!to) {
        log(`end of ladder after ${from}`);
        await ctx.session.synthetic({ sessionID, text: END_OF_LADDER, resume: false }).catch((e) => log(`synthetic failed: ${e}`));
        return;
      }
      log(`switch ${from} -> ${to}`);
      await ctx.session.switchModel({ sessionID, model: splitRef(to) });
      await ctx.session.synthetic({
        sessionID,
        text: `${switchedLine(from, to)} Continue the previous task from where it stopped.`,
        resume: true,
      });
    }

    // New sessions: if the configured model is already used up today, move the session
    // to the first live rung before its first request.
    async function onCreated(sessionID, data) {
      const m = data?.model ?? data?.info?.model;
      if (!m || !sessionID) return;
      const ref = `${m.providerID}/${m.id ?? m.modelID}`;
      const dead = exhaustedNow(load());
      if (!dead.includes(ref)) return;
      const to = nextModel(ref, dead) ?? firstLive(dead);
      if (to) {
        log(`new session ${sessionID} starts on live rung ${to} (not ${ref})`);
        await ctx.session.switchModel({ sessionID, model: splitRef(to) }).catch((e) => log(`switch failed: ${e}`));
      }
    }

    const controller = new AbortController();
    void (async () => {
      try {
        for await (const ev of ctx.event.subscribe({ signal: controller.signal })) {
          const type = ev?.type ?? "";
          const data = ev?.data ?? ev?.properties ?? {};
          const sessionID = data.sessionID ?? data.info?.id ?? data.id;
          if (debug && /error|fail|retry/.test(type)) log(`raw ${type} ${JSON.stringify(data).slice(0, 600)}`);
          if (type === "session.created") onCreated(sessionID, data).catch((e) => log(`created: ${e}`));
          const err = data.error ?? (/error|failed/.test(type) ? data : null);
          if (err && /error|fail|retry/.test(type)) onError(sessionID, err, type).catch((e) => log(`onError: ${e}`));
        }
      } catch (e) { log(`subscribe ended: ${e}`); }
    })();
    return () => controller.abort();
  },
};
