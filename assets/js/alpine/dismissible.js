import Alpine from "@alpinejs/csp";

Alpine.data("dismissible", () => ({
  visible: true,
  dismiss() {
    this.visible = false;
  },
}));
