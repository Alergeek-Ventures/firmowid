import { defineConfig } from "deepsec/config";

export default defineConfig({
  projects: [
    { id: "firmowid.security-audit", root: ".." },
    // <deepsec:projects-insert-above>
  ],
});
