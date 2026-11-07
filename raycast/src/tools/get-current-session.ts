import { getCurrentSession } from "../lib/api";
import { authorize } from "../lib/auth";

export default async function tool() {
  return (await getCurrentSession({ token: await authorize() })) ?? null;
}
