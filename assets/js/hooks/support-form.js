import posthog from "posthog-js";

export const SupportForm = {
  mounted() {
    this.handleEvent("support:submit", async ({ message, email }) => {
      if (!posthog.conversations?.isAvailable()) {
        this.pushEventTo(this.el, "support_ticket_failed", { reason: "unavailable" });
        return;
      }

      try {
        const response = await posthog.conversations.sendMessage(message, { email }, true);

        if (!response) {
          this.pushEventTo(this.el, "support_ticket_failed", { reason: "failed" });
          return;
        }

        this.el.querySelector("textarea").value = "";
        this.pushEventTo(this.el, "support_ticket_sent", { ticket_id: response.ticket_id });
      } catch (error) {
        console.warn("PostHog Support ticket creation failed", error);
        this.pushEventTo(this.el, "support_ticket_failed", { reason: "failed" });
      }
    });
  },
};
