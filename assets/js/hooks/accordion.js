export const Accordion = {
  mounted() {
    this.el.querySelectorAll("[data-accordion-content]").forEach((content) => {
      content.style.maxHeight = "0px";
      content.style.overflow = "hidden";
      content.style.transition = "max-height 0.25s ease";
    });

    this.el.querySelectorAll("[data-accordion-trigger]").forEach((trigger) => {
      trigger.addEventListener("click", (e) => {
        const item = e.currentTarget.closest("[data-accordion-item]");
        const content = item.querySelector("[data-accordion-content]");
        const isOpen = item.classList.contains("open");

        if (isOpen) {
          item.classList.remove("open");
          content.style.maxHeight = "0px";
        } else {
          // Close others
          this.el
            .querySelectorAll("[data-accordion-item].open")
            .forEach((openItem) => {
              openItem.classList.remove("open");
              openItem.querySelector(
                "[data-accordion-content]",
              ).style.maxHeight = "0px";
            });

          item.classList.add("open");
          content.style.maxHeight = content.scrollHeight + "px";
        }
      });
    });
  },
};
