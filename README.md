<div align="center">

# OwlKnit

**A modern framework for Roblox, spiritual successor to Knit.**

Structure your `Server/Client` logic in a clean, secure, and maintainable way.

[![Wally](https://img.shields.io/badge/wally-avadakedavra6%2Fowlknit-blue?style=for-the-badge)](https://wally.run/package/avadakedavra6/owlknit)
[![Docs](https://img.shields.io/badge/docs-owlknit--docs.vercel.app-black?style=for-the-badge&logo=vercel)](https://owlknit-docs.vercel.app/)
[![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)](LICENSE)

### [**Full documentation, API, examples and changelog**](https://owlknit-docs.vercel.app/)

</div>

---

## What is OwlKnit?

OwlKnit organizes your Roblox game around two simple entities:

| Entity | Context | Role |
|:---|:---:|:---|
| **Service** | Server | Business logic, database, security, global state |
| **Controller** | Client | UI, input handling, visual effects, communication with Services |

Services and Controllers never communicate directly everything goes through OwlKnit's abstractions (`Signal`, `Property`, `Client` methods), guaranteeing a clean and secure architecture by design.

### Key features

- **Clear lifecycle** - `OwlInit` (sequential) > `OwlStart` (parallel) > `OwlDestroy`
- **Automated hooks** - no need to manually connect `PlayerAdded`, `CharacterAdded`, etc...
- **Dependency resolution** - automatic topological sort between your Services/Controllers
- **Built-in middleware** - RateLimiter, TypeChecker, global or perservice middleware
- **Component system** - natively handled with extensions
- **OwlData** - full persistence layer with secure sessions and automatic hooks
- **Abstracted Comm** - `Property`, `Signal` and `Client` methods (RemoteFunctions) with zero boilerplate

The full API, detailed guides and complete examples are available at **[owlknit-docs.vercel.app](https://owlknit-docs.vercel.app/)**.

---

## Installation

### Via Wally (recommended)

Add this to your `wally.toml`:

```toml
[dependencies]
owlknit = "avadakedavra6/owlknit@1.0.3"
```

Then install:

```bash
wally install
```

### Via Rojo (without Wally)

Clone the repo directly into your project:

```bash
git clone https://github.com/AvadaKedavra6/OwlKnit.git
```

Then link the resulting folder to `ReplicatedStorage` in your Rojo `default.project.json`, and sync with:

```bash
rojo serve
```

### Via `.rbxm` file

Don't want to use Wally or Rojo? Download the latest ready to use `.rbxm` directly from this repo's **[Releases](../../releases)** tab and drag it into Roblox Studio (`Insert from Roblox Model`).

---

## Useful links

| | |
|---|---|
| Documentation, API abd changelog | [owlknit-docs.vercel.app](https://owlknit-docs.vercel.app/) |
| Wally package | [wally.run/package/avadakedavra6/owlknit](https://wally.run/package/avadakedavra6/owlknit) |
| Releases (.rbxm) | [Releases](../../releases) |

---

<div align="center">

*Thanks for using my framework, I work a lot on it :)*
*Thanks also Sleitnick for the big inspiration*

Made with ❤️ by **Dev_Abrahel** / **Morax**

</div>