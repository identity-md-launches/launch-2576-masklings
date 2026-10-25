# Vendored dependencies

OpenZeppelin/openzeppelin-contracts v5.0.2
Source: https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2
Archive SHA-256: 18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a
Included: 6 ordinary source/license files

foundry-rs/forge-std v1.9.7
Source: https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
Archive SHA-256: 45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94
Included: 30 ordinary source/license files

OpenZeppelin includes only the transitive ERC-20 source dependencies and its MIT license.
forge-std includes its complete src/ tree and both upstream licenses, for tests only.
Files are unmodified upstream sources. No submodules or install step are needed.

Verify vendored file integrity with `sha256sum -c DEPENDENCIES.sha256`.
