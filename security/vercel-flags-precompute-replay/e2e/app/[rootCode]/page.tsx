import { navigationFlag, rootFlags } from '../../flags';

export default async function Page({
  params,
}: {
  params: Promise<{ rootCode: string }>;
}) {
  const { rootCode } = await params;
  const navigation = await navigationFlag(rootCode, rootFlags);
  return <main>navigation={navigation}</main>;
}
