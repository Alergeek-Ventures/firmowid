export const AssistantChat = {
  mounted() {
    this.storageKey = this.el.dataset.storageKey;
    this.conversationId = this.el.dataset.conversationId;
    this.followingLatest = true;
    this.messageList = this.el.querySelector("#assistant-messages");
    this.input = this.el.querySelector("#assistant-input");
    this.newMessages = this.el.querySelector("#assistant-new-messages");
    this.input.value = sessionStorage.getItem(this.draftKey(this.conversationId)) || "";

    this.storeDraft = () => sessionStorage.setItem(this.draftKey(this.conversationId), this.input.value);
    this.onRestart = () => this.pushEvent("new_conversation", { path: window.location.pathname });
    this.onScroll = () => {
      const distanceFromBottom = this.messageList.scrollHeight - this.messageList.scrollTop - this.messageList.clientHeight;
      this.followingLatest = distanceFromBottom < 48;
      if (this.followingLatest) this.newMessages.hidden = true;
    };
    this.scrollToLatest = () => {
      this.followingLatest = true;
      this.followLatest();
      this.newMessages.hidden = true;
    };
    this.onKey = (event) => {
      if (event.key === "Escape" && this.el.dataset.open === "true") {
        event.preventDefault();
        event.stopPropagation();
        this.pushEvent("close", {});
      }
      if (
        event.target === this.input &&
        event.key === "Enter" &&
        !event.shiftKey &&
        !event.isComposing &&
        matchMedia("(pointer: fine)").matches
      ) {
        event.preventDefault();
        if (!this.input.form.querySelector('[type="submit"]').disabled) this.input.form.requestSubmit();
      }
    };
    this.updateViewportInset = () => {
      const viewport = window.visualViewport;
      const keyboard = viewport ? Math.max(0, window.innerHeight - viewport.height - viewport.offsetTop) : 0;
      const consent = document.getElementById("cookie-consent-banner");
      this.el.style.setProperty("--assistant-bottom-obstruction", `${Math.max(keyboard, consent?.offsetHeight || 0)}px`);
    };

    this.input.addEventListener("input", this.storeDraft);
    this.messageList.addEventListener("scroll", this.onScroll, { passive: true });
    this.el.addEventListener("keydown", this.onKey);
    this.el.addEventListener("assistant-restart", this.onRestart);
    this.newMessages.addEventListener("click", this.scrollToLatest);
    window.visualViewport?.addEventListener("resize", this.updateViewportInset);
    this.contentObserver = new ResizeObserver(() => this.followLatest());
    this.contentObserver.observe(this.el.querySelector("#assistant-content"));
    this.consentObserver = new ResizeObserver(this.updateViewportInset);
    const consent = document.getElementById("cookie-consent-banner");
    if (consent) this.consentObserver.observe(consent);

    this.handleEvent("assistant-token", ({ text }) => {
      const target = this.el.querySelector("#assistant-live-text");
      if (target) target.append(document.createTextNode(text));
      this.followLatest();
    });
    this.handleEvent("assistant-reset-stream", () => {
      const target = this.el.querySelector("#assistant-live-text");
      if (target) target.textContent = "";
      this.followLatest();
    });
    this.handleEvent("assistant-clear-draft", () => {
      this.syncConversation();
      this.input.value = "";
      sessionStorage.removeItem(this.draftKey(this.conversationId));
    });
    this.handleEvent("assistant-sent", ({ conversation_id, source_id }) => {
      this.syncConversation();
      sessionStorage.removeItem(this.draftKey(source_id));
      sessionStorage.removeItem(this.draftKey(conversation_id));
      this.input.value = "";
      this.scrollToLatest();
      this.input.focus({ preventScroll: true });
    });
    this.handleEvent("assistant-focus", ({ open }) => {
      requestAnimationFrame(() => {
        let target = this.input;
        if (!open) target = this.el.querySelector("#assistant-launcher");
        else if (this.el.dataset.historyOpen === "true") target = this.el.querySelector("#assistant-history-toggle");
        target.focus({ preventScroll: true });
      });
    });
    this.updateViewportInset();
    this.pushEvent("restore", {
      open: sessionStorage.getItem(`${this.storageKey}:open`) === "true",
      conversation_id: sessionStorage.getItem(`${this.storageKey}:conversation`),
    });
  },
  updated() {
    this.syncConversation();
    sessionStorage.setItem(`${this.storageKey}:open`, this.el.dataset.open);
    sessionStorage.setItem(`${this.storageKey}:conversation`, this.conversationId);
    this.followLatest();
  },
  draftKey(id) {
    return `${this.storageKey}:${id}:draft`;
  },
  syncConversation() {
    const nextId = this.el.dataset.conversationId;
    if (nextId === this.conversationId) return;
    this.storeDraft();
    this.conversationId = nextId;
    this.input.value = sessionStorage.getItem(this.draftKey(nextId)) || "";
    this.followingLatest = true;
    this.newMessages.hidden = true;
    const liveText = this.el.querySelector("#assistant-live-text");
    if (liveText) liveText.textContent = "";
  },
  followLatest() {
    if (this.el.dataset.historyOpen === "true") {
      this.newMessages.hidden = true;
      return;
    }
    if (this.followingLatest) this.messageList.scrollTop = this.messageList.scrollHeight;
    else if (this.el.dataset.open === "true") this.newMessages.hidden = false;
  },
  destroyed() {
    this.input.removeEventListener("input", this.storeDraft);
    this.messageList.removeEventListener("scroll", this.onScroll);
    this.el.removeEventListener("keydown", this.onKey);
    this.el.removeEventListener("assistant-restart", this.onRestart);
    this.newMessages.removeEventListener("click", this.scrollToLatest);
    window.visualViewport?.removeEventListener("resize", this.updateViewportInset);
    this.contentObserver.disconnect();
    this.consentObserver.disconnect();
  },
};
