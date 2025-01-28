export const ScrollStyle = {
    mounted() {
        this.offset = parseInt(this.el.dataset.scrollOffset) || 100;
        this.classes = this.el.dataset.classes?.split(" ") || [];

        // Bind the scroll handler
        this._onScroll = this._handleScroll.bind(this);
        window.addEventListener("scroll", this._onScroll);

        // Initial check
        this._handleScroll();
    },

    destroyed() {
        window.removeEventListener("scroll", this._onScroll);
    },

    _handleScroll() {
        if (window.scrollY > this.offset) {
            this.classes.forEach((className) => {
                this.el.classList.add(className);
            });
        } else {
            this.classes.forEach((className) => {
                this.el.classList.remove(className);
            });
        }
    }
}; 