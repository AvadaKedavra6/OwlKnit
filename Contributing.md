# Contribute to OwlKnit

Thank you for wanting to contribute to OwlKnit! 

Before opening a PR or an issue, please take two minutes to read this document—it helps avoid unnecessary back-and-forth.

## There are two ways to contribute, don't confuse them

- **Contribute to the framework** (this repo): you modify `Owl.lua`, `OwlServer.lua`, `OwlComponent.lua`, etc.. the heart of OwlKnit itself, that's what this document is about.
- **Create an addon**: You write an external script that connects to OwlKnit via `Owl.RegisterAddon(...)`. **It never affects this repo**, an addon is a separate project that you host wherever you like and submit via Discord or my messages so it can be listed on the website, don't open a PR here to propose an addon.

If you're torn between the two: Does your change alter the framework's behavior for **everyone** or is it an optional feature that only developers who install it will use? The first case = PR here, the second = addon.

---

## Before opening a PR

### Understanding Architecture

```
Owl (Main ModuleScript, init.lua)
├── OwlServer.lua  <- Service Bootstrap, Remotes, Server Lifecycle
├── OwlClient.lua  <- Controller bootstrap, service proxies, Client Lifecycle
├── OwlComponent.lua  <- Components System (CollectionService)
├── OwlAction.lua  <- Unified input (keyboard/controller/touchscreen)
├── OwlScheduler.lua  <- Budgeted Task/Frame/Render/Deferred queues
├── OwlFlags.lua  <- Cross-server feature flags
├── OwlShared.lua  <- Common Utilities + Logger
└── Addons/ <- Self-scanned file, NOT for your PR (see above)
```

If your PR affects a file you don't fully understand, mention it in the description we'd rather have a PR that's honest about its limitations than one that breaks something without warning.

### Code style, this is typed Luau not free-form Lua

OwlKnit aims for zero `any` (with documented exceptions). Specifically:

- **No new `any`** without a comment right above it explaining EXACTLY why Luau can't do it any other way (dynamic dispatch by method name, type duality between two incompatible concrete forms, etc.). “I couldn't figure out how to type this properly” is not a sufficient reason, ask for help in the issue/PR rather than just throwing in an unexplained `any`.
- Prefer `unknown` over `any` wherever the value doesn't need to be manipulated directly this forces an explicit cast in the right place rather than letting silent ambiguity slip through.
- A module that needs the type of another module (e.g., `OwlServer.lua` needs the type of `RegisteredService`) **should duplicate a minimal local interface** rather than performing a cross-module `require()` at load time this avoids circular dependencies. See `OwlLike`/`Service` in `OwlServer.lua` as an example.
- Empty table + guard `type(x) == “table”`: Prefer `unknown` + explicit cast over a direct `:: any` cast.

### File formats

Follow the existing style:

```lua
--[[
				Owl - Name Of The Module
				A line describing what this module does.
--]]

-- > // Variables \\ < --

...

-- > // Func : Name Of The Func \\ < --

function Module.MyFunction(arg: string): boolean
	...
end
```

- Use tabs for indentation, not spaces.
- Error messages should be prefixed with `[Owl]` or `[Owl - ModuleName]`, always using `assert(...)`, never a bare `error()` without context.
- Use the Logger (`OwlShared.Logger(“Scope”)`) rather than raw `print`/`warn` for anything that isn't a blocking error.

### Document the WHY, not just the WHAT

A comment that explains *what* the code does is often redundant with the code itself. A comment that explains *why* that specific choice (rather than an obvious alternative) was made is the one that adds value. 

If your PR makes a non-obvious choice (working around a Luau limitation, execution order that matters, a trade-off between performance and readability), explain it in a comment right there.

### Process

1. **Fork, create a branch from `main`** with a descriptive branch name (`fix/scheduler-frame-budget`, `feat/addon-hot-reload`...).
2. **Targeted PR**: one change, one PR. A PR that combines a bug fix with an unrelated new feature will likely be split into multiple PRs.
3. **Test in Studio before submitting**, both server AND client if your change affects both. OwlKnit does not currently have automated CI it’s up to you to verify that it compiles and runs.
4. **Describe the change** in the PR: what problem it solves or what functionality it adds, and most importantly **does it break anything that already exists? ** A silent breaking change will not be accepted if it’s necessary, state it explicitly and explain why there was no backward-compatible alternative.
5. A reviewer may request changes this is normal, not a rejection.

### What we probably won't accept

- A feature that should be an addon rather than an addition to the core (see above).
- A change that introduces a significant external dependency for a minor need.
- Untyped code “because it's faster to write” if you're too lazy to type, say so in the PR and we'll help you but we won't merge untyped code by default.

---

## Report a bug

A helpful report includes:

- **OwlKnit version** involved.
- **Server, client or both?**
- **Steps to reproduce** a minimal code snippet that triggers the issue is better than a vague description.
- **Expected vs observed behavior** including the full error or warning message if you have one (copy and paste the entire stack trace, not just the first line).

## Propose a feature for the core

Open an issue BEFORE creating a pull request for any non-trivial feature this prevents you from writing code that will be rejected for architectural reasons that a quick discussion would have revealed. Minor fixes and improvements can go straight into a pull request.

---

## Code of Conduct

Be respectful. Technical disagreements are normal and welcome but aggression or contempt toward a contributor is not, regardless of their skill level. Poor PR is corrected with constructive feedback not with sarcasm.

---

## License

By contributing to OwlKnit, you agree that your contributions will be licensed under the [MIT License](./LICENSE).

***Thank you to everyone who will contribute and help OwlKnit grow and stay alive for years to come!***
