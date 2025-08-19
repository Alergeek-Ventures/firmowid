export default {
  mounted() {
    this.el.addEventListener("showPopover", this.showPopover.bind(this));
    this.el.addEventListener("hidePopover", this.hidePopover.bind(this));
  },

  showPopover() {
    const reference = document.getElementById(this.el.dataset.reference);
    if (!reference) {
      console.warn(
        `Popover: reference element with id "${this.el.dataset.reference}" not found`
      );
      return;
    }

    const { computePosition, autoUpdate, flip } = window.FloatingUIDOM;

    document.body.style.pointerEvents = "none";

    this.cleanUp = autoUpdate(reference, this.el, () => {
      computePosition(reference, this.el, {
        placement: this.el.dataset.placement,
        middleware: [flip()],
      }).then(({ x, y }) => {
        Object.assign(this.el.style, {
          top: `${y}px`,
          left: `${x}px`,
        });
      });
    });
  },

  hidePopover() {
    document.body.style.pointerEvents = null;
    this.cleanUp?.();
    this.cleanUp = null;
  },

  updated() {
    const isVisible = this.cleanUp != null;
    if (isVisible) {
      this.hidePopover();
      this.showPopover();
    }
  },

  destroyed() {
    this.hidePopover();
    this.el.removeEventListener("showPopover", this.showPopover.bind(this));
    this.el.removeEventListener("hidePopover", this.hidePopover.bind(this));
  },
};
