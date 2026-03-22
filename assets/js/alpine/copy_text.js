import Alpine from "@alpinejs/csp";

Alpine.data("copyText", () => ({
  copied: false,
  async copy() {
    const text = this.$el.dataset.copyValue;
    await navigator.clipboard.writeText(text);
    this.copied = true;
    setTimeout(() => (this.copied = false), 2000);
  },
}));
