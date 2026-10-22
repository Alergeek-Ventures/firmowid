export const LandingNavbarTheme = {
  mounted() {
    this.raf = null;
    this.updateTheme = () => {
      this.raf = null;

      const nav = this.el.querySelector("nav");
      const darkSurfaces = document.querySelectorAll("[data-landing-dark-surface]");

      if (!nav || darkSurfaces.length === 0) {
        this.el.dataset.theme = "light";
        return;
      }

      const navRect = nav.getBoundingClientRect();
      const sampleY = navRect.top + navRect.height / 2;

      const overlapsDarkSurface = Array.from(darkSurfaces).some((surface) => {
        const surfaceRect = surface.getBoundingClientRect();

        return sampleY >= surfaceRect.top && sampleY <= surfaceRect.bottom;
      });

      this.el.dataset.theme = overlapsDarkSurface ? "dark" : "light";
    };

    this.scheduleUpdate = () => {
      if (this.raf) return;
      this.raf = requestAnimationFrame(this.updateTheme);
    };

    this.scheduleUpdate();
    window.addEventListener("scroll", this.scheduleUpdate, { passive: true });
    window.addEventListener("resize", this.scheduleUpdate);
  },

  updated() {
    this.scheduleUpdate();
  },

  destroyed() {
    if (this.raf) cancelAnimationFrame(this.raf);
    window.removeEventListener("scroll", this.scheduleUpdate);
    window.removeEventListener("resize", this.scheduleUpdate);
  },
};
