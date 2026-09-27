import {
  discountFlag,
  navigationFlag,
  pricingFlags,
  rootFlags,
} from '../../../../flags';

export default async function Page({
  params,
}: {
  params: Promise<{ rootCode: string; pricingCode: string }>;
}) {
  const { rootCode, pricingCode } = await params;
  const navigation = await navigationFlag(rootCode, rootFlags);
  const discount = await discountFlag(pricingCode, pricingFlags);
  return <main>navigation={navigation};discount={discount}</main>;
}
