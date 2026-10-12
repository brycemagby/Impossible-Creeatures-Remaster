// Protocol tests against the Node relay (the Cloudflare one shares room.js).
import { test } from "node:test";
import assert from "node:assert/strict";
import WebSocket from "ws";
import { startRelay } from "../src/node_server.js";

// RELAY_URL=ws://localhost:8787 runs these against `wrangler dev` instead.
const BASE = process.env.RELAY_URL || "ws://localhost:18787";
const server = process.env.RELAY_URL ? null : startRelay(18787);
test.after(() => server?.close());

function connect(path) {
  const ws = new WebSocket(`${BASE}${path}`);
  const inbox = [];
  const waiters = [];
  ws.on("message", (data, isBinary) => {
    const item = isBinary ? new Uint8Array(data) : JSON.parse(data.toString());
    const waiter = waiters.shift();
    if (waiter) waiter(item);
    else inbox.push(item);
  });
  ws.next = () => inbox.length ? Promise.resolve(inbox.shift()) : new Promise((resolve) => waiters.push(resolve));
  ws.closed = new Promise((resolve) => ws.on("close", (code) => resolve(code)));
  return ws;
}

function packet(target, channel, mode, payload) {
  const out = new Uint8Array(6 + payload.length);
  new DataView(out.buffer).setInt32(0, target, true);
  out[4] = channel;
  out[5] = mode;
  out.set(payload, 6);
  return out;
}

function source(bytes) {
  return new DataView(bytes.buffer, bytes.byteOffset).getInt32(0, true);
}

test("host gets a code, guest joins, packets flow both ways", async () => {
  const host = connect("/host");
  const welcome = await host.next();
  assert.equal(welcome.type, "welcome");
  assert.equal(welcome.id, 1);
  assert.match(welcome.code, /^[A-Z2-9]{4}$/);

  const guest = connect(`/join/${welcome.code.toLowerCase()}`);
  const guestWelcome = await guest.next();
  assert.equal(guestWelcome.type, "welcome");
  assert.ok(guestWelcome.id > 1);
  assert.deepEqual(guestWelcome.peers, [1]);
  const joined = await host.next();
  assert.deepEqual(joined, { type: "peer_joined", id: guestWelcome.id });

  host.send(packet(guestWelcome.id, 1, 2, [7, 8, 9]));
  const toGuest = await guest.next();
  assert.equal(source(toGuest), 1);
  assert.deepEqual([...toGuest.slice(4)], [1, 2, 7, 8, 9]);

  guest.send(packet(0, 0, 0, [42]));
  const toHost = await host.next();
  assert.equal(source(toHost), guestWelcome.id);
  assert.deepEqual([...toHost.slice(6)], [42]);

  guest.close();
  assert.deepEqual(await host.next(), { type: "peer_left", id: guestWelcome.id });
  host.close();
});

test("joining a code with no host is refused", async () => {
  const guest = connect("/join/ZZZZ");
  const message = await guest.next();
  assert.equal(message.type, "error");
  assert.equal(await guest.closed, 4000);
});

test("the room closes when the host leaves", async () => {
  const host = connect("/host");
  const { code } = await host.next();
  const guest = connect(`/join/${code}`);
  await guest.next();
  await host.next();
  host.close();
  assert.equal((await guest.next()).type, "error");
  await guest.closed;
});

test("host can kick a guest", async () => {
  const host = connect("/host");
  const { code } = await host.next();
  const guest = connect(`/join/${code}`);
  const { id } = await guest.next();
  await host.next();
  host.send(JSON.stringify({ type: "kick", id }));
  assert.equal((await guest.next()).type, "error");
  await guest.closed;
  host.close();
});
