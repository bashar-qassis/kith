import Alpine from "@alpinejs/csp";

Alpine.data("recoveryCodes", (codes) => ({
  codes: codes,
  copied: false,
  async copyAll() {
    await navigator.clipboard.writeText(this.codes.join("\n"));
    this.copied = true;
    setTimeout(() => (this.copied = false), 2000);
  },
  downloadTxt() {
    const blob = new Blob([this.codes.join("\n")], { type: "text/plain" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = "kith-recovery-codes.txt";
    a.click();
    URL.revokeObjectURL(url);
  },
}));
