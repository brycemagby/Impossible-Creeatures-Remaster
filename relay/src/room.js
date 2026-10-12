// One game room: a host and the players who joined with its code. The relay
// doesn't understand the game; it only passes packets between the people in a
// room, so players never need to open ports or know each other's address.
//
// Protocol (spoken by scripts/net/relay_peer.gd):
//
// Connect with a WebSocket to /host (open a room and get a code) or
// /join/CODE. Control messages are JSON text:
//   relay -> player  {"type":"welcome","id":N,"code":"ABCD","peers":[ids]}
//                    {"type":"peer_joined","id":N}   (host only)
//                    {"type":"peer_left","id":N}     (host only)
//                    {"type":"error","message":"..."} then the socket closes
//   host  -> relay   {"type":"kick","id":N}
// Game packets are binary:
//   player -> relay  [i32 LE target][u8 channel][u8 mode][payload]
//                    target 0 = everyone else, N = that player, -N = all but N
//   relay -> player  the same packet with the sender's id in place of target
// The host is always id 1 and guests get random ids, like Godot's ENet peers.
// When the host leaves, the room closes.

export const MAX_PLAYERS = 8;
export const HEADER_SIZE = 6;
export const MAX_PACKET = 1 << 20;
// No 0/O or 1/I, so codes are easy to read out.
const CODE_LETTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
export const CODE_LENGTH = 4;
export const CLOSE_NORMAL = 1000;
export const CLOSE_REFUSED = 4000;

export function newCode() {
  let code = "";
  const bytes = crypto.getRandomValues(new Uint8Array(CODE_LENGTH));
  for (const byte of bytes) code += CODE_LETTERS[byte % CODE_LETTERS.length];
  return code;
}

export function cleanCode(text) {
  const code = String(text || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  return code.length === CODE_LENGTH ? code : null;
}

// "/host" -> {action: "host"}, "/join/abcd" -> {action: "join", code: "ABCD"}.
export function parseRoute(pathname) {
  const parts = pathname.split("/").filter(Boolean);
  if (parts.length === 1 && parts[0] === "host") return { action: "host" };
  if (parts.length === 2 && parts[0] === "join") {
    const code = cleanCode(parts[1]);
    return code ? { action: "join", code } : { action: "bad_code" };
  }
  return null;
}

function newGuestId(taken) {
  for (;;) {
    const id = 2 + (crypto.getRandomValues(new Uint32Array(1))[0] % 0x7ffffffd);
    if (!taken.has(id)) return id;
  }
}

function sendJson(ws, message) {
  try {
    ws.send(JSON.stringify(message));
  } catch {
    // Already closing; its close event tidies up.
  }
}

export function refuse(ws, message) {
  sendJson(ws, { type: "error", message });
  try {
    ws.close(CLOSE_REFUSED, message.slice(0, 120));
  } catch {
    // Already closed.
  }
}

// A room works on a list of members, [{id, ws}], that the caller keeps (a Map
// on Node, the Durable Object's hibernatable sockets on Cloudflare), so the
// room itself holds no state between calls.
export class Room {
  constructor(code, members) {
    this.code = code;
    this.members = members;
  }

  host() {
    return this.members().find((m) => m.id === 1) || null;
  }

  // Decides the id for a new socket, or refuses it (returns 0). The caller
  // records the id and then calls welcome().
  admit(ws, wantsHost) {
    const members = this.members();
    if (wantsHost) {
      if (members.length > 0) return 0;
      return 1;
    }
    if (!members.some((m) => m.id === 1)) {
      refuse(ws, "No game with that code. Check the code with the host.");
      return 0;
    }
    if (members.length >= MAX_PLAYERS) {
      refuse(ws, "That game is full");
      return 0;
    }
    return newGuestId(new Set(members.map((m) => m.id)));
  }

  welcome(ws, id) {
    // Guests only talk to the host, like Godot clients only know the server.
    const peers = id === 1 ? this.members().filter((m) => m.id !== 1).map((m) => m.id) : [1];
    sendJson(ws, { type: "welcome", id, code: this.code, peers });
    if (id !== 1) {
      const host = this.host();
      if (host) sendJson(host.ws, { type: "peer_joined", id });
    }
  }

  // A message from member [id]: a JSON control message or a binary packet.
  message(id, data) {
    if (typeof data === "string") {
      this.control(id, data);
      return;
    }
    const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
    if (bytes.length < HEADER_SIZE || bytes.length > MAX_PACKET) return;
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const target = view.getInt32(0, true);
    // Guests may only reach the host.
    if (id !== 1 && target !== 1 && target !== 0) return;
    const out = new Uint8Array(bytes);
    new DataView(out.buffer).setInt32(0, id, true);
    for (const member of this.members()) {
      if (member.id === id) continue;
      if (id !== 1 && member.id !== 1) continue;
      if (target > 0 && member.id !== target) continue;
      if (target < 0 && member.id === -target) continue;
      try {
        member.ws.send(out);
      } catch {
        // Closing; its close event tidies up.
      }
    }
  }

  control(id, text) {
    let message;
    try {
      message = JSON.parse(text);
    } catch {
      return;
    }
    if (message && message.type === "kick" && id === 1 && message.id !== 1) {
      const member = this.members().find((m) => m.id === message.id);
      if (member) refuse(member.ws, "The host removed you from the game");
    }
  }

  // Member [id] disconnected (already gone from members()).
  left(id) {
    if (id === 1) {
      for (const member of this.members()) refuse(member.ws, "The host left");
      return;
    }
    const host = this.host();
    if (host) sendJson(host.ws, { type: "peer_left", id });
  }
}
