export const AssistantChat = {
  mounted() {
    this.key = this.el.dataset.storageKey;
    this.pinned = true;
    this.log = this.el.querySelector("#assistant-messages");
    this.input = this.el.querySelector("#assistant-input");
    this.newMessages = this.el.querySelector("#assistant-new-messages");
    this.input.value = sessionStorage.getItem(`${this.key}:draft`) || "";

    this.onInput = () => sessionStorage.setItem(`${this.key}:draft`, this.input.value);
    this.onScroll = () => {
      this.pinned = this.log.scrollHeight - this.log.scrollTop - this.log.clientHeight < 48;
      if (this.pinned) this.newMessages.hidden = true;
    };
    this.toLatest = () => {
      this.pinned = true;
      this.follow();
      this.newMessages.hidden = true;
    };
    this.onKey = (event) => {
      if (event.key === "Escape" && this.el.dataset.open === "true") {
        event.preventDefault();
        event.stopPropagation();
        this.pushEvent("close", {});
      }
      if (event.target === this.input && event.key === "Enter" && !event.shiftKey && !event.isComposing && matchMedia("(pointer: fine)").matches) {
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

    this.input.addEventListener("input", this.onInput);
    this.log.addEventListener("scroll", this.onScroll, { passive: true });
    this.el.addEventListener("keydown", this.onKey);
    this.newMessages.addEventListener("click", this.toLatest);
    window.visualViewport?.addEventListener("resize", this.updateViewportInset);
    this.contentObserver = new ResizeObserver(() => this.follow());
    this.contentObserver.observe(this.el.querySelector("#assistant-content"));
    this.consentObserver = new ResizeObserver(this.updateViewportInset);
    const consent = document.getElementById("cookie-consent-banner");
    if (consent) this.consentObserver.observe(consent);

    this.handleEvent("assistant-token", ({ text }) => {
      const target = this.el.querySelector("#assistant-live-text");
      if (target) target.append(document.createTextNode(text));
      this.follow();
    });
    this.handleEvent("assistant-reset-stream", () => {
      const target = this.el.querySelector("#assistant-live-text");
      if (target) target.textContent = "";
      this.follow();
    });
    this.handleEvent("assistant-sent", () => {
      this.input.value = "";
      sessionStorage.removeItem(`${this.key}:draft`);
      this.toLatest();
      this.input.focus({ preventScroll: true });
    });
    this.handleEvent("assistant-focus", ({ open, prompt }) => {
      if (prompt && this.input.value.trim() === "") {
        this.input.value = prompt;
        this.onInput();
      }
      requestAnimationFrame(() => {
        const target = open ? this.input : this.el.querySelector("#assistant-launcher");
        target.focus({ preventScroll: true });
      });
    });
    this.updateViewportInset();
    this.pushEvent("restore", { open: sessionStorage.getItem(`${this.key}:open`) === "true" });
  },
  updated() {
    sessionStorage.setItem(`${this.key}:open`, this.el.dataset.open);
    this.follow();
  },
  follow() {
    if (this.pinned) this.log.scrollTop = this.log.scrollHeight;
    else if (this.el.dataset.open === "true") this.newMessages.hidden = false;
  },
  destroyed() {
    this.input.removeEventListener("input", this.onInput);
    this.log.removeEventListener("scroll", this.onScroll);
    this.el.removeEventListener("keydown", this.onKey);
    this.newMessages.removeEventListener("click", this.toLatest);
    window.visualViewport?.removeEventListener("resize", this.updateViewportInset);
    this.contentObserver.disconnect();
    this.consentObserver.disconnect();
  },
};
