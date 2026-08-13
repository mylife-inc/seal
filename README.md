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
topology — are encrypted, and reading them requires a key held by the people
who maintain CodeSeal.

There is nothing to clone. Without a key a checkout is a directory of opaque
blobs, and the binaries below are built from those blobs by CI on a runner that
holds the key for the length of a build and no longer.

That is the product demonstrating itself: a public repository, an unreadable
source tree, and releases that come out of it anyway.

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
