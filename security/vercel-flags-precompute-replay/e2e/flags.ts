import { flag } from 'flags/next';

export const navigationFlag = flag<string>({
  key: 'navigation',
  options: ['classic', 'new'],
  decide: () => 'new',
});

export const discountFlag = flag<string>({
  key: 'discount',
  options: ['none', 'vip'],
  decide: () => 'none',
});

export const rootFlags = [navigationFlag] as const;
export const pricingFlags = [discountFlag] as const;
