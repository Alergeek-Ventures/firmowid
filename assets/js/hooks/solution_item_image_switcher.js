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

    this.handleMouseLeave = this._handleMouseLeave.bind(this);
    this.el.addEventListener('mouseleave', this.handleMouseLeave);
  },

  destroyed() {
    if (this.el) {
      this.el.removeEventListener('mouseenter', this.handleMouseEnter);
      this.el.removeEventListener('mouseleave', this.handleMouseLeave);
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
      this.arrow.classList.remove('opacity-100');
      this.arrow.classList.add('opacity-0');
    }
    if(this.defaultImage) {
      this.defaultImage.classList.add('md:opacity-0');
    }
  },

  _handleMouseLeave() {
    // Hide all images
    this.images.forEach((img) => {
      img.classList.remove('opacity-100');
      img.classList.add('opacity-0');
    });

    // Show arrow and default image when reverting
    if (this.arrow) {
      this.arrow.classList.add('opacity-100');
      this.arrow.classList.remove('opacity-0');
    }
    if(this.defaultImage) {
      this.defaultImage.classList.remove('md:opacity-0');
    }
  }
};
