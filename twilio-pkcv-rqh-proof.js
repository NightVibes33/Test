const crypto = require("crypto");

function sha256(s) {
  return crypto.createHash("sha256").update(s).digest("hex");
}

function enc(str) {
  return encodeURIComponent(decodeURIComponent(String(str)))
    .replace(/\*/g, "%2A")
    .replace(/%7E/g, "~");
}

// Current twilio-node behavior.
function nodeCanonicalQuery(params) {
  return Object.entries(params)
    .map(([key, value]) => `${key}=${value}`)
    .sort()
    .map((param) => {
      const [key, value] = param.split("=");
      return `${enc(key)}=${enc(value)}`;
    })
    .join("&");
}

// Expected semantics: split a pair at the first '=' only; '=' characters in
// the value remain part of the value and therefore remain authenticated.
function specCanonicalQuery(params) {
  return Object.entries(params)
    .map(([key, value]) => `${enc(key)}=${enc(value)}`)
    .sort()
    .join("&");
}

function canonicalRequest(query) {
  return [
    "GET",
    "/2010-04-01/Accounts/AC00000000000000000000000000000000/Messages.json",
    query,
    "authorization:Basic TEST",
    "host:api.twilio.com",
    "",
    "authorization;host",
    ""
  ].join("\n");
}

const a = { PageToken: "abc=ONE" };
const b = { PageToken: "abc=TWO" };

const nodeA = nodeCanonicalQuery(a);
const nodeB = nodeCanonicalQuery(b);
const specA = specCanonicalQuery(a);
const specB = specCanonicalQuery(b);

const rqhNodeA = sha256(canonicalRequest(nodeA));
const rqhNodeB = sha256(canonicalRequest(nodeB));
const rqhSpecA = sha256(canonicalRequest(specA));
const rqhSpecB = sha256(canonicalRequest(specB));

console.log(JSON.stringify({
  requestA: a,
  requestB: b,
  currentTwilioNode: {
    canonicalA: nodeA,
    canonicalB: nodeB,
    rqhA: rqhNodeA,
    rqhB: rqhNodeB,
    collision: rqhNodeA === rqhNodeB
  },
  expectedSemantics: {
    canonicalA: specA,
    canonicalB: specB,
    rqhA: rqhSpecA,
    rqhB: rqhSpecB,
    collision: rqhSpecA === rqhSpecB
  }
}, null, 2));

if (rqhNodeA !== rqhNodeB) throw new Error("twilio-node collision did not reproduce");
if (rqhSpecA === rqhSpecB) throw new Error("control unexpectedly collided");

console.log("PASS: distinct query values produce identical current twilio-node PKCV rqh.");
