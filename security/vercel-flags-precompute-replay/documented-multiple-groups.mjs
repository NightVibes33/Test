import assert from 'node:assert/strict';
import { flag, serialize, deserialize } from 'flags/next';

const secret = Buffer.alloc(32, 0x43).toString('base64url');

// Mirrors Vercel's documented "Multiple groups" setup.
// rootFlags apply broadly; pricingFlags apply only to /pricing.
const navigationFlag = flag({
  key: 'navigation',
  options: ['classic', 'new'],
  decide: () => 'new',
});

const discountFlag = flag({
  key: 'discount',
  options: ['none', 'vip'],
  decide: () => 'none',
});

const rootFlags = [navigationFlag];
const pricingFlags = [discountFlag];

// A legitimate signed code that would be exposed in the rootCode URL segment.
const rootCode = await serialize(rootFlags, ['new'], secret);

// Normal interpretation under its intended group.
const intended = await deserialize(rootFlags, rootCode, secret);

// Attacker copies the exact same rootCode into the pricingCode URL segment.
// No secret, modification, or re-signing occurs.
const replayed = await deserialize(pricingFlags, rootCode, secret);

console.log('MULTI_GROUP intended.navigation=' + intended.navigation);
console.log('MULTI_GROUP replayed.discount=' + replayed.discount);
console.log('MULTI_GROUP source_segment=rootCode');
console.log('MULTI_GROUP target_segment=pricingCode');
console.log('MULTI_GROUP token_modified=false');

assert.equal(intended.navigation, 'new');
assert.equal(replayed.discount, 'vip');

console.log('MULTI_GROUP RESULT=PASS');
