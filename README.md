<p align="center">
  <img src="Resources/Logo.png" width="96" height="96" alt="Postino icon">
</p>

<h1 align="center">Postino</h1>

<p align="center">A native, fully local HTTP client for macOS.</p>

<p align="center">
  <a href="https://github.com/Dome015/postino/releases">Download for macOS</a> ·
</p>

## Installation

Requires macOS 13 or later. Release downloads are for Apple Silicon Macs.

1. Download the Postino ZIP from [Releases](https://github.com/Dome015/postino/releases).
2. Unzip it and drag **Postino.app** into **Applications**.
3. Open Postino. If macOS blocks the first launch, use `sudo xattr -rd com.apple.quarantine /path/to/Postino.app`.

## Usage

1. Create a request with **⌘N**, or select one from a collection.
2. Choose the HTTP method, enter the URL, and add a body, parameters, headers, or authentication as needed.
3. Press **⌘Return** to send. Click **Cancel** to stop a running request.
4. Inspect the response, use **Pretty JSON** for readability, or **⌘F** to search either body. **Copy body** copies the full response; **⇧⌘S** saves the original response to a file.
5. Press **⌘S** to save your request. A dot on its tab marks unsaved changes.

Right-click collections and folders to add requests or folders. Drag items to move or reorder them, and drag the dividers to resize the sidebar and request/response areas.

### Bring your Postman workspace

- **Import** or **⌘I** opens Postman collection and environment JSON files.
- **Export** or **⇧⌘E** saves the selected collection as Postman v2.1 JSON. Save request changes before exporting.
- Choose an environment at the top right. Use the sliders button or **⌥⌘E** to edit variables, then reference them as `{{variable_name}}`. Environments have their own **Export** button.

Postman scripts and collection runners are not executed.

---

> **Disclosure:** this project was built and tested exclusively with AI; I only took care of the design of the application and some manual testing. If you do not approve of AI, please refrain from using this project.

For development, builds, and technical documentation, see [AGENTS.md](AGENTS.md).
