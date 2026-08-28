export const FileUploadDragState = {
  mounted() {
    const el = this.el;
    const set = (value) => el.setAttribute("data-dragging", value);
    const onDragEnter = (e) => {
      e.preventDefault();
      set("true");
    };
    const onDragLeave = (e) => {
      if (!el.contains(e.relatedTarget)) set("false");
    };
    const onDrop = () => set("false");
    const onDragOver = (e) => {
      e.preventDefault();
      set("true");
    };
    el.addEventListener("dragenter", onDragEnter);
    el.addEventListener("dragover", onDragOver);
    el.addEventListener("dragleave", onDragLeave);
    el.addEventListener("drop", onDrop);
  },
  updated() {
    if (!this.el.hasAttribute("data-dragging")) {
      this.el.setAttribute("data-dragging", "false");
    }
  }
};
