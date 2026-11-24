export const FocusOnMount = {
  mounted() {
    // On phones a focused field would bring up the keyboard and hide the
    // timesheet bar, so the field waits for a tap there.
    if (window.matchMedia("(max-width: 767.98px)").matches) return;
    this.el.focus();
    this.el.select();
  },
};
