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

    window.addEventListener("beforeunload", this.beforeUnloadHandler);
    window.addEventListener("phx:unsaved-changed", this.unsavedChangedHandler);
  },

  destroyed() {
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);
    window.removeEventListener(
      "phx:unsaved-changed",
      this.unsavedChangedHandler,
    );
  },
};
