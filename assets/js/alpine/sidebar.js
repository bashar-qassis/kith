import Alpine from "@alpinejs/csp";

Alpine.data("sidebar", () => ({
  sidebarOpen: localStorage.getItem("kith:sidebar") !== "collapsed",
  toggle() {
    this.sidebarOpen = !this.sidebarOpen;
    localStorage.setItem(
      "kith:sidebar",
      this.sidebarOpen ? "expanded" : "collapsed"
    );
  },
}));

Alpine.data("userMenu", () => ({
  userMenu: false,
  toggle() {
    this.userMenu = !this.userMenu;
  },
  close() {
    this.userMenu = false;
  },
}));
