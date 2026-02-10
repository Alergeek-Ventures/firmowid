export const ConfirmLeave = {
  mounted() {
    this.unsaved = false;

    this.beforeUnloadHandler = (event) => {
      if (this.unsaved) {
        event.preventDefault();
        event.returnValue = "";
      }
    };

    this.unsavedChangedHandler = (e) => {
      this.unsaved = e.detail.value;
    };

    // Intercept LiveView navigation (browser back, internal links)
    this.navigateHandler = (event) => {
      if (this.unsaved) {
        const confirmed = window.confirm(
          "Masz niezapisane zmiany. Czy na pewno chcesz opuścić stronę?",
        );
        if (!confirmed) {
          event.preventDefault();
        }
      }
    };

    window.addEventListener("beforeunload", this.beforeUnloadHandler);
    window.addEventListener("phx:unsaved-changed", this.unsavedChangedHandler);
    window.addEventListener("phx:navigate", this.navigateHandler);
  },

  destroyed() {
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);
    window.removeEventListener(
      "phx:unsaved-changed",
      this.unsavedChangedHandler,
    );
    window.removeEventListener("phx:navigate", this.navigateHandler);
  },
};
