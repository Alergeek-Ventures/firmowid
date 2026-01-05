export const SolutionItemImageSwitcher = {
  mounted() {
    // Get the image container and all images within it
    const imageContainerId = this.el.dataset.imageContainer;
    this.imageContainer = document.getElementById(imageContainerId);
    
    if (!this.imageContainer) {
      console.warn(`Image container not found: ${imageContainerId}`);
      return;
    }

    this.index = parseInt(this.el.dataset.solutionIndex) || 0;
    
    this.images = Array.from(this.imageContainer.querySelectorAll('img'));
    
    // Get optional arrow element
    this.arrow = document.getElementById("functionality-arrow") || null;
    this.defaultImage = this.imageContainer.querySelector("#default-photo") || null;
    
    // Setup event listeners
    this.handleMouseEnter = this._handleMouseEnter.bind(this);
    this.el.addEventListener('mouseenter', this.handleMouseEnter);
  },

  destroyed() {
    if (this.el) {
      this.el.removeEventListener('mouseenter', this.handleMouseEnter);
    }
  },

  _handleMouseEnter() {
    // Hide all images
    this.images.forEach((img) => {
      img.classList.remove('opacity-100');
      img.classList.add('opacity-0');
    });

    // Show the image at the corresponding index
    if (this.images[this.index]) {
      this.images[this.index].classList.remove('opacity-0');
      this.images[this.index].classList.add('opacity-100');
    }

    // Hide arrow when showing non-default image
    if (this.arrow) {
      this.arrow.classList.add('hidden');
      this.arrow.classList.add('lg:hidden');
    }
    if(this.defaultImage && this.index !== 3) {
      this.defaultImage.classList.add('lg:opacity-0');
    }
  },
};
