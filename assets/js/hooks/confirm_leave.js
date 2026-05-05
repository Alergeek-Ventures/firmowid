export const ConfirmLeave = {
  mounted() {
    this.unsaved = this.el.dataset.unsaved === "true";
    this.confirmMessage =
      "Masz niezapisane zmiany. Czy na pewno chcesz opuścić stronę?";

    this.beforeUnloadHandler = (event) => {
      if (this.unsaved) {
        event.preventDefault();
        event.returnValue = "";
      }
    };

    this.unsavedChangedHandler = (e) => {
      this.unsaved = Boolean(e.detail.value);
    };

    this.clickHandler = (event) => {
      if (!this.unsaved) return;

      const guardedTarget =
        event.target instanceof Element
          ? event.target.closest("[data-confirm-leave]")
          : null;

      if (!guardedTarget || !this.el.contains(guardedTarget)) return;

      const confirmed = window.confirm(
        guardedTarget.dataset.confirmLeaveMessage || this.confirmMessage,
      );

      if (!confirmed) {
        event.preventDefault();
        event.stopImmediatePropagation();
        event.stopPropagation();
      }
    };

    window.addEventListener("beforeunload", this.beforeUnloadHandler);
    window.addEventListener("phx:unsaved-changed", this.unsavedChangedHandler);
    this.el.addEventListener("click", this.clickHandler, true);
  },

  destroyed() {
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);
    window.removeEventListener(
      "phx:unsaved-changed",
      this.unsavedChangedHandler,
    );
    this.el.removeEventListener("click", this.clickHandler, true);
  },
};
