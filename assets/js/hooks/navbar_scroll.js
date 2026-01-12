/**
 * NavbarScroll hook
 * 
 * Detects when the navbar actually overlaps with dark sections (like cta_footer)
 * and toggles the navbar styling to maintain contrast.
 */
export const NavbarScroll = {
  mounted() {
    this.setupOverlapDetection();
  },

  setupOverlapDetection() {
    const navbar = this.el;
    const navbarContainer = navbar.querySelector("#navbar-container");
    const navbarLogo = navbar.querySelector("#navbar-logo");
    const navbarLinks = navbar.querySelectorAll(".navbar-link");
    const darkSection = document.querySelector("#cta-footer");

    if (!darkSection) return;

    // Scroll event listener for continuous overlap detection
    const scrollHandler = () => {
      const isOverlapping = this.checkOverlap(navbar, darkSection);
      this.updateNavbarStyle(isOverlapping, navbarContainer, navbarLogo, navbarLinks);
    };

    window.addEventListener("scroll", scrollHandler, { passive: true });
    
    // Initial check
    scrollHandler();

    this.scrollHandler = scrollHandler;
  },

  checkOverlap(navbar, darkSection) {
    const navbarRect = navbar.getBoundingClientRect();
    const navbarCenter = navbarRect.top + navbarRect.height / 2;
    const darkSectionRect = darkSection.getBoundingClientRect();

    // Check if the dark section's top is within the navbar's visible area
    return (
      navbarCenter > darkSectionRect.top &&
      navbarCenter < darkSectionRect.bottom
    );
  },

  updateNavbarStyle(isOverlapping, navbarContainer, navbarLogo, navbarLinks) {
    if (isOverlapping) {
      // Switch to light navbar for dark backgrounds
      navbarContainer.classList.add("bg-white");
      navbarContainer.classList.remove("bg-black");
      navbarLinks.forEach(link => {
        link.classList.add("text-white");
        link.classList.remove("text-black");
      });
      navbarLogo.classList.add("text-white");
      navbarLogo.classList.remove("text-black");
    } else {
      // Switch back to default navbar
      navbarContainer.classList.remove("bg-white");
      navbarContainer.classList.add("bg-black");
      navbarLinks.forEach(link => {
        link.classList.remove("text-white");
        link.classList.add("text-black");
      });
      navbarLogo.classList.remove("text-white");
      navbarLogo.classList.add("text-black");
    }
  },

  destroyed() {
    if (this.scrollHandler) {
      window.removeEventListener("scroll", this.scrollHandler);
    }
  }
};
