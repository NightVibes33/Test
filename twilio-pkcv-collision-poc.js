// Minimal reproduction of the current twilio-node PKCV query canonicalizer bug.
// Mirrors RequestCanonicalizer.getCanonicalizedQueryParams().

function customEncode(str) {
  return encodeURIComponent(decodeURIComponent(str))
    .replace(/\*/g, "%2A")
    .replace(/%7E/g, "~");
}

function asciiCompare(a, b) {
  if (a < b) return -1;
  return a > b ? 1 : 0;
}

function canonicalize(queryParams) {
  return Object.entries(queryParams)
    .map(([key, value]) => `${key}=${value}`)
    .sort(asciiCompare)
    .map((param) => {
      const [key, value] = param.split("=");
      return `${customEncode(key)}=${customEncode(value)}`;
    })
    .join("&");
}

const cases = [
  { token: "abc=ONE" },
  { token: "abc=TWO" },
  { token: "abc=" },
  { token: "abc" },
];

const outputs = cases.map((x) => ({
  input: x,
  canonical: canonicalize(x),
}));

console.table(outputs);

if (new Set(outputs.map((x) => x.canonical)).size !== 1) {
  throw new Error("Expected all inputs to collide");
}

console.log("CONFIRMED: distinct query values produce the same PKCV canonical query.");
