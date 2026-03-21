let debounceTimer = null

const CommandPalette = {
  mounted() {
    // Global keyboard shortcut
    this.handleKeydown = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault()
        const el = this.el
        if (el._x_dataStack) {
          window.Alpine.$data(el).show()
        }
      }
    }
    window.addEventListener("keydown", this.handleKeydown)

    // Listen for the sidebar button dispatch
    this.handleOpenEvent = () => {
      const el = this.el
      if (el._x_dataStack) {
        window.Alpine.$data(el).show()
      }
    }
    window.addEventListener("kith:open-command-palette", this.handleOpenEvent)

    // Listen for search results from the server (push_event)
    this.handleEvent("command_palette_results", ({ contacts }) => {
      const data = window.Alpine.$data(this.el)
      if (data) data.receiveResults(contacts || [])
    })

    // Listen for search events from Alpine
    this.el.addEventListener("command-palette:search", (e) => {
      const query = e.detail.query
      clearTimeout(debounceTimer)
      debounceTimer = setTimeout(() => {
        this.pushEvent("command_palette_search", { query })
      }, 250)
    })

    // Listen for navigate events from Alpine
    this.el.addEventListener("command-palette:navigate", (e) => {
      const path = e.detail.path
      this.pushEvent("command_palette_navigate", { path })
    })
  },

  destroyed() {
    window.removeEventListener("keydown", this.handleKeydown)
    window.removeEventListener("kith:open-command-palette", this.handleOpenEvent)
    clearTimeout(debounceTimer)
  }
}

export default CommandPalette
