const ListItemRemovalAnimation = {
    mounted() {
        this.handleRemoval = ({ id }) => {
            const row = document.getElementById(`${id}-row`);
            const cells = document.querySelectorAll(`[data-overflow-hider-id="${id}"]`);
            if (row) {
                cells.forEach(cell => {
                    cell.classList.add(
                        'animate-list-item-removal',
                        'overflow-hidden'
                    )
                });
                row.classList.add(
                    'animate-list-item-removal',
                    'overflow-hidden'
                );
                row.childNodes.forEach(child => {
                    if (child.classList && child.classList.contains("py-2")) {
                        child.classList.add("!p-0")
                    }
                })

                let currentRow = row;

                const rowCount = document.querySelectorAll('tbody tr').length;

                for (let i = 0; i < rowCount; i++) {
                    const nextRow = currentRow.nextElementSibling;
                    if (nextRow) {
                        setTimeout(() => {
                            nextRow.classList.add('transition-all', 'duration-300', '-translate-y-3')
                        }, 10 * i);
                        currentRow = nextRow;
                    }
                }

            }
        };

        window.addEventListener("phx:mark-for-removal", (e) => this.handleRemoval(e.detail));
    },

    destroyed() {
        window.removeEventListener("phx:mark-for-removal", this.handleRemoval);
    }
};

export { ListItemRemovalAnimation }; 