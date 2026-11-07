import { listProjects } from "../lib/api";
import { authorize } from "../lib/auth";

export default async function tool() {
  return listProjects({ token: await authorize() });
}
