export const ConfirmLeave = {
  mounted() {
    this.unsaved = false;

    this.beforeUnloadHandler = (event) => {
      if (this.unsaved) {
        event.preventDefault();
        event.returnValue = "";
      }
    };

    window.addEventListener("beforeunload", this.beforeUnloadHandler);

    window.addEventListener("phx:unsaved-changed", (e) => {
      this.unsaved = e.detail.value;
    });
  },

  destroyed() {
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);
  },
};
