import "trix"

const TrixEditor = {
  mounted() {
    this.suppressChange = false
    const inputName = this.el.dataset.input
    this.hiddenInput = this.el.querySelector(`input[name="${inputName}"]`)
    this.editor = this.el.querySelector("trix-editor")

    if (!this.editor) return

    // Sync content changes to hidden input
    this.changeHandler = (_event) => {
      if (this.suppressChange) return
      if (this.hiddenInput) {
        this.hiddenInput.value = this.editor.editor.getDocument().toString().trim()
          ? this.editor.innerHTML
          : ""
      }
    }

    this.editor.addEventListener("trix-change", this.changeHandler)

    // Pre-populate if content exists
    const initialContent = this.hiddenInput?.value
    if (initialContent && initialContent.trim() !== "") {
      this.suppressChange = true
      this.editor.editor.loadHTML(initialContent)
      this.suppressChange = false
    }
  },

  updated() {
    // When LiveView re-renders, check if we need to update editor content
    const inputName = this.el.dataset.input
    this.hiddenInput = this.el.querySelector(`input[name="${inputName}"]`)
    const newContent = this.hiddenInput?.value || ""
    const currentContent = this.editor?.innerHTML || ""

    if (newContent !== currentContent && this.editor) {
      this.suppressChange = true
      this.editor.editor.loadHTML(newContent)
      this.suppressChange = false
    }
  },

  destroyed() {
    if (this.editor && this.changeHandler) {
      this.editor.removeEventListener("trix-change", this.changeHandler)
    }
  }
}

export default TrixEditor
