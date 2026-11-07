import { withAccessToken } from "@raycast/utils";

import SessionForm from "./components/session-form";
import { authorize } from "./lib/auth";
import { withQueryClient } from "./lib/query-client";

function StartSession() {
  return <SessionForm kind="start" returnToRoot />;
}

export default withAccessToken({ authorize })(withQueryClient(StartSession));
