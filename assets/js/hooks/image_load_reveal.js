export const ImageLoadReveal = {
  mounted() {
    this.revealImage = () => revealWhenDecoded(this.el);

    if (this.el.complete) {
      this.revealImage();
      return;
    }

    this.el.addEventListener("load", this.revealImage, { once: true });
    this.el.addEventListener("error", this.revealImage, { once: true });
  },

  destroyed() {
    this.el.removeEventListener("load", this.revealImage);
    this.el.removeEventListener("error", this.revealImage);
  }
};

async function revealWhenDecoded(image) {
  try {
    await image.decode();
  } catch (_error) {
    // Broken images should still release the reserved space instead of staying hidden.
  }

  window.requestAnimationFrame(() => {
    image.dataset.imageLoaded = "true";
  });
}
