export const FileUploadDragNDrop = {
    updated() {
        this.attachListeners();
    },

    mounted() {
        this.attachListeners();
    },

    attachListeners() {
        const dropArea = this.el;

        const showDropArea = () => {
            dropArea.classList.remove("hidden");
            dropArea.classList.add("flex", "opacity-100");
        };

        let hideDropAreaTimeout = null;

        const hideDropArea = () => {
            setTimeout(() => {
                dropArea.classList.add("hidden");
                dropArea.classList.remove("flex");
            }, 160);
            dropArea.classList.remove("opacity-100");
        };

        const handleDragover = (e) => {
            e.preventDefault();
            e.stopPropagation();
            showDropArea();
            clearTimeout(hideDropAreaTimeout);
            hideDropAreaTimeout = setTimeout(hideDropArea, 200);
        };

        dropArea.addEventListener("dragover", handleDragover);
        dropArea.addEventListener("dragenter", handleDragover);

        document.body.addEventListener("dragover", handleDragover);
        document.body.addEventListener("dragenter", handleDragover);
    }
}; 