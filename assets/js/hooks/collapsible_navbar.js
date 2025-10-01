// Store all mounted instances
window.CollapsibleNavbarInstances = window.CollapsibleNavbarInstances || [];

export const CollapsibleNavbar = {
  mounted() {
    this.offset = parseInt(this.el.dataset.scrollOffset) || 0;
    this.classes = this.el.dataset.classes?.split(" ") || [];
    this.isOverrideButton = this.el.dataset.isOverrideButton === "true";

    // Track this instance
    window.CollapsibleNavbarInstances.push(this);

    // Bind scroll handler
    this._onScroll = this._handleScroll.bind(this);
    window.addEventListener("scroll", this._onScroll);

    // Initial check
    this._handleScroll();

    // If this element is the override button, bind click
    if (this.isOverrideButton) {
      this.handleOverride = this._toggleForcedOpen.bind(this);
      this.el.addEventListener("click", this.handleOverride);
    }
  },

  updated() {
    this._handleScroll();
  },

  destroyed() {
    window.removeEventListener("scroll", this._onScroll);
    if (this.isOverrideButton) {
      this.el.removeEventListener("click", this.handleOverride);
    }

    // Remove from instances array
    const idx = window.CollapsibleNavbarInstances.indexOf(this);
    if (idx > -1) window.CollapsibleNavbarInstances.splice(idx, 1);
  },

  _toggleForcedOpen() {
    window.isNavbarForcedOpen = !window.isNavbarForcedOpen;

    // Notify all instances to recheck
    window.CollapsibleNavbarInstances.forEach((instance) =>
      instance._handleScroll(),
    );
  },

  _handleScroll() {
    if (this.isOverrideButton) {
      shouldAdd = window.isNavbarForcedOpen || window.scrollY > this.offset;

      // toggle icon visibility
      const burger = this.el.querySelector(".burger-icon");
      const xIcon = this.el.querySelector(".x-icon");

      if (burger && xIcon) {
        if (window.isNavbarForcedOpen) {
          burger.classList.add("hidden");
          xIcon.classList.remove("hidden");
        } else {
          burger.classList.remove("hidden");
          xIcon.classList.add("hidden");
        }
      }
    } else {
      shouldAdd = window.scrollY > this.offset && !window.isNavbarForcedOpen;
    }

    this.classes.forEach((className) => {
      this.el.classList.toggle(className, shouldAdd);
    });
  },
};
