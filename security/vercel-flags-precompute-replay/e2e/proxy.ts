import { NextResponse, type NextRequest } from 'next/server';
import { precompute } from 'flags/next';
import { rootFlags, pricingFlags } from './flags';

export const config = { matcher: ['/', '/pricing'] };

export async function proxy(request: NextRequest) {
  if (request.nextUrl.pathname === '/') {
    const rootCode = await precompute(rootFlags);
    return NextResponse.rewrite(new URL(`/${rootCode}`, request.url));
  }

  const rootCode = await precompute(rootFlags);
  const pricingCode = await precompute(pricingFlags);
  return NextResponse.rewrite(
    new URL(`/${rootCode}/pricing/${pricingCode}`, request.url),
  );
}
