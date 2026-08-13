# CodeSeal

CodeSeal keeps sensitive source files encrypted inside a Git repository, so the
repository can be public while the source that matters stays unreadable —
including to anyone who administers the hosting.

Development carries on normally. Files are decrypted in your working tree,
encrypted again on commit, and CI decrypts them on a runner for the length of a
build.

**Documentation: [codeseal.shebka.net](https://codeseal.shebka.net)**

## This repository

Most of what you can see here is scaffolding. The parts that carry the design —
the CLI implementation, the Portal, the specifications and the deployment
topology — are encrypted, and reading them requires a key nobody publishes.

That is the product demonstrating itself. A `.sgit` directory, a set of opaque
blobs, and a build that works anyway.

```
sgit clone <repo>      # clone and decrypt, if you hold a key
sgit status            # what is protected, and how
```

## Install

```
curl -fsSL https://raw.githubusercontent.com/mylife-inc/releases/main/codeseal/install.sh | sh
```

macOS and Linux, x86-64 and arm64. Every release publishes checksums and the
installer verifies one before putting anything on your PATH.

## Licence

`sgit` is free to use. See [codeseal.shebka.net](https://codeseal.shebka.net)
for terms covering the hosted Portal.

---

© Shebka LLC
