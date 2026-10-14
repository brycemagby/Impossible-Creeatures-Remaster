// The relay as a plain Node server, for playing and testing on your own
// machine without Cloudflare: `npm run local` (PORT defaults to 8787, the
// same port `wrangler dev` uses).
import { WebSocketServer } from "ws";
import { Room, parseRoute, newCode, refuse } from "./room.js";

export function startRelay(port = 8787) {
  const rooms = new Map(); // code -> Map(id -> ws)
  const server = new WebSocketServer({ port, maxPayload: 1 << 20 });

  const roomFor = (code) => {
    if (!rooms.has(code)) rooms.set(code, new Map());
    const sockets = rooms.get(code);
    return {
      sockets,
      room: new Room(code, () =>
        [...sockets].filter(([, ws]) => ws.readyState === 1).map(([id, ws]) => ({ id, ws }))),
    };
  };

  server.on("connection", (ws, request) => {
    const route = parseRoute(new URL(request.url, "http://relay").pathname);
    if (!route) return refuse(ws, "Connect to /host or /join/CODE");
    if (route.action === "bad_code") return refuse(ws, "That code doesn't look right. Codes are 4 letters.");
    let code = route.code;
    if (route.action === "host") {
      do code = newCode(); while (rooms.has(code));
    }
    const { sockets, room } = roomFor(code);
    const id = room.admit(ws, route.action === "host");
    if (id === 0) {
      if (sockets.size === 0) rooms.delete(code);
      return;
    }
    sockets.set(id, ws);
    room.welcome(ws, id);
    ws.on("message", (data, isBinary) => {
      room.message(id, isBinary ? new Uint8Array(data.buffer, data.byteOffset, data.byteLength) : data.toString());
    });
    ws.on("close", () => {
      sockets.delete(id);
      room.left(id);
      if (sockets.size === 0) rooms.delete(code);
    });
  });
  return server;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const port = Number(process.env.PORT || 8787);
  startRelay(port);
  console.log(`Relay listening on ws://localhost:${port}`);
}
