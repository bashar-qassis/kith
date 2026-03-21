import Alpine from "@alpinejs/csp";

Alpine.data("lightbox", () => ({
  open: false,
  currentSrc: "",
  currentName: "",
  show(src, name) {
    this.currentSrc = src;
    this.currentName = name;
    this.open = true;
  },
  close() {
    this.open = false;
  },
}));
