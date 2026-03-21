import Alpine from "@alpinejs/csp";

Alpine.data("passwordStrength", () => ({
  pw: "",
  get visible() {
    return this.pw.length > 0;
  },
  get barClass() {
    if (this.pw.length < 8) return "bg-error w-1/4";
    if (this.pw.length < 12) return "bg-warning w-1/2";
    if (this.pw.length < 16) return "bg-info w-3/4";
    return "bg-success w-full";
  },
  get textClass() {
    if (this.pw.length < 8) return "text-error";
    if (this.pw.length < 12) return "text-warning";
    if (this.pw.length < 16) return "text-info";
    return "text-success";
  },
  get label() {
    if (this.pw.length < 8) return "Too short";
    if (this.pw.length < 12) return "Fair";
    if (this.pw.length < 16) return "Good";
    return "Strong";
  },
}));
