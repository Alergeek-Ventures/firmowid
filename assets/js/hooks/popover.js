import { computePosition, autoUpdate, flip, size } from "@floating-ui/dom";

// Distance kept between a popover and the viewport edges.
const VIEWPORT_PADDING = 16;

export default {
  mounted() {
    this.el.addEventListener("showPopover", this.showPopover.bind(this));
    this.el.addEventListener("hidePopover", this.hidePopover.bind(this));
    // Choosing a menu item closes the menu. Deferred so LiveView first handles the
    // item's own phx-click; focus returns to the trigger unless something else
    // (for example a modal opened by the item) has taken it.
    this.el.addEventListener("click", (event) => {
      if (!event.target.closest('[role="menuitem"]')) return;

      setTimeout(() => {
        this.el.style.display = "none";
        this.hidePopover();

        const active = document.activeElement;
        if (!active || active === document.body || this.el.contains(active)) {
          document.getElementById(this.el.dataset.reference)?.focus();
        }
      });
    });
  },

  showPopover() {
    const reference = document.getElementById(this.el.dataset.reference);
    if (!reference) {
      console.warn(
        `Popover: reference element with id "${this.el.dataset.reference}" not found`
      );
      return;
    }

    document.body.style.pointerEvents = "none";

    this.cleanUp = autoUpdate(reference, this.el, () => {
      computePosition(reference, this.el, {
        placement: this.el.dataset.placement,
        strategy: this.el.dataset.strategy || "absolute",
        middleware: [
          flip({ padding: VIEWPORT_PADDING }),
          // Exposes the room left in the viewport, so long content can scroll within it.
          size({
            padding: VIEWPORT_PADDING,
            apply: ({ availableHeight, elements }) => {
              elements.floating.style.setProperty(
                "--popover-available-height",
                `${availableHeight}px`
              );
            },
          }),
        ],
      }).then(({ x, y }) => {
        Object.assign(this.el.style, {
          position: this.el.dataset.strategy || "absolute",
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
