import assert from 'node:assert/strict';
import { flag, serialize, deserialize } from 'flags/next';

const secret = Buffer.alloc(32, 0x41).toString('base64url');

// Source flag group: harmless/public variant.
const publicPlan = flag({
  key: 'public-plan',
  options: ['free', 'pro'],
  decide: () => 'pro',
});

// Target flag group: security-sensitive application decision.
const accessRole = flag({
  key: 'access-role',
  options: ['user', 'admin'],
  decide: () => 'user',
});

// A valid signed token for public-plan='pro' (option index 1).
const token = await serialize([publicPlan], ['pro'], secret);

// Baseline: token decodes correctly in its original context.
const baseline = await deserialize([publicPlan], token, secret);
assert.equal(baseline['public-plan'], 'pro');

// Replay the exact same signed token in a different flag context.
// The signature verifies because it covers only the encoded value bytes.
// The token is not bound to the flag key or options metadata.
const replayed = await deserialize([accessRole], token, secret);

console.log('TOKEN_REPLAY baseline_public_plan=' + baseline['public-plan']);
console.log('TOKEN_REPLAY replayed_access_role=' + replayed['access-role']);
console.log('TOKEN_REPLAY same_token=true');
console.log('TOKEN_REPLAY expected_target_default=user');

assert.equal(replayed['access-role'], 'admin');

console.log('TOKEN_REPLAY RESULT=PASS');
