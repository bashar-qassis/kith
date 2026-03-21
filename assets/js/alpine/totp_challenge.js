import Alpine from "@alpinejs/csp";

Alpine.data("totpChallenge", () => ({
  recoveryMode: false,
  toggleMode() {
    this.recoveryMode = !this.recoveryMode;
  },
  get modeLabel() {
    return this.recoveryMode
      ? "Use authenticator code instead"
      : "Use a recovery code instead";
  },
  autoSubmit(event) {
    const val = event.target.value;
    if (val.length === 6 && /^\d{6}$/.test(val)) {
      this.$nextTick(() => this.$refs.totpForm.submit());
    }
  },
}));
