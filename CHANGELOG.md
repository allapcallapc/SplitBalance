# Changelog

## [3.4.0](https://github.com/allapcallapc/SplitBalance/compare/v3.3.0...v3.4.0) (2026-09-05)


### Features

* make all built-in Material icons available for categories ([#80](https://github.com/allapcallapc/SplitBalance/issues/80)) ([42e99aa](https://github.com/allapcallapc/SplitBalance/commit/42e99aa1424bf665a368cc25333a032b1ebc46d8))
* ping staging Supabase on a schedule to prevent auto-pause ([ed2d382](https://github.com/allapcallapc/SplitBalance/commit/ed2d3821a03e5b52044175eac01494d599cf5856))
* search bills by date or date range on the bills list ([#78](https://github.com/allapcallapc/SplitBalance/issues/78)) ([f8d4486](https://github.com/allapcallapc/SplitBalance/commit/f8d4486ae4fe8cbdff2fab632565d5a69f7084f6))

## [3.3.0](https://github.com/allapcallapc/SplitBalance/compare/v3.2.0...v3.3.0) (2026-09-05)


### Features

* jump from category summary to bills filtered by that category ([#71](https://github.com/allapcallapc/SplitBalance/issues/71)) ([f7f0aa8](https://github.com/allapcallapc/SplitBalance/commit/f7f0aa8dbcba109a26441fb9dbca0616f5766d4b))
* track recovered amounts against bills ([#76](https://github.com/allapcallapc/SplitBalance/issues/76)) ([876415f](https://github.com/allapcallapc/SplitBalance/commit/876415f61e0fa22f8244b8ab1d31811046b88377))


### Bug Fixes

* dismiss pending-bill notification when tapped, not just "No" ([#75](https://github.com/allapcallapc/SplitBalance/issues/75)) ([d0b05f1](https://github.com/allapcallapc/SplitBalance/commit/d0b05f111cd39c5beed68c6e78dc5ba0a3c7736a))
* fix summary screen color clashes in pink and teal themes ([#72](https://github.com/allapcallapc/SplitBalance/issues/72)) ([49846fb](https://github.com/allapcallapc/SplitBalance/commit/49846fb43319ae7a1e0760eaf7c295ea68964b51))
* remove Clear All Configuration button from config screen ([#74](https://github.com/allapcallapc/SplitBalance/issues/74)) ([b2e4180](https://github.com/allapcallapc/SplitBalance/commit/b2e4180ea7c8930e298a1ed9c699d9f5f9ed4ecb))
* use distinct empty-state text when filters exclude all bills ([7bd906a](https://github.com/allapcallapc/SplitBalance/commit/7bd906a17c80d7c2480030bb6d6d3db214725286))

## [3.2.0](https://github.com/allapcallapc/SplitBalance/compare/v3.1.0...v3.2.0) (2026-08-16)


### Features

* include notification title in the Google Pay bill note ([#65](https://github.com/allapcallapc/SplitBalance/issues/65)) ([e1db84e](https://github.com/allapcallapc/SplitBalance/commit/e1db84e6c25a7d9b81c33c2d86c9996d9c046146))
* replace app icon and automate icon generation with flutter_launcher_icons ([99d4c07](https://github.com/allapcallapc/SplitBalance/commit/99d4c074c3d861981c4aece2a64361a1a9c040b4))

## [3.1.0](https://github.com/allapcallapc/SplitBalance/compare/v3.0.0...v3.1.0) (2026-08-08)


### Features

* add sort control to the bills screen ([#48](https://github.com/allapcallapc/SplitBalance/issues/48)) ([ccebd2d](https://github.com/allapcallapc/SplitBalance/commit/ccebd2dd8eefca8fd3397dfa42f6e117bf2ee570))
* move summary balance calculation to narrow aggregated queries ([#55](https://github.com/allapcallapc/SplitBalance/issues/55)) ([0204404](https://github.com/allapcallapc/SplitBalance/commit/0204404d54efdc0a436961b97370c3c8af030f9d))
* show per-person expense counts in Summary Statistics card ([#45](https://github.com/allapcallapc/SplitBalance/issues/45)) ([4d5fc43](https://github.com/allapcallapc/SplitBalance/commit/4d5fc431d931242873d8a16344d0f745be6bf625))
* tappable Summary rows to drill into category and Total detail charts ([#61](https://github.com/allapcallapc/SplitBalance/issues/61)) ([66c7e20](https://github.com/allapcallapc/SplitBalance/commit/66c7e202f24436f5ec7a46f3943a4efbc2c6e428))


### Bug Fixes

* aggregate person/household bill totals server-side via Postgres RPCs ([#58](https://github.com/allapcallapc/SplitBalance/issues/58)) ([1f1bc10](https://github.com/allapcallapc/SplitBalance/commit/1f1bc10c7cb172c83663eebc4a2cf57bcd9afebf))
* restore previously selected tab after a refresh instead of forcing Bills ([#60](https://github.com/allapcallapc/SplitBalance/issues/60)) ([80adb7a](https://github.com/allapcallapc/SplitBalance/commit/80adb7a421ef39d71737f0eaeeb328b603e333b3))

## [3.0.0](https://github.com/allapcallapc/SplitBalance/compare/v2.1.1...v3.0.0) (2026-08-07)


### ⚠ BREAKING CHANGES

* require Supabase URL/key via --dart-define for every build ([#52](https://github.com/allapcallapc/SplitBalance/issues/52))

### Features

* add live preview deployments for PRs and main ([#44](https://github.com/allapcallapc/SplitBalance/issues/44)) ([90152ba](https://github.com/allapcallapc/SplitBalance/commit/90152baa86f246685e129574f90df896a1ccf478))
* require Supabase URL/key via --dart-define for every build ([#52](https://github.com/allapcallapc/SplitBalance/issues/52)) ([180947d](https://github.com/allapcallapc/SplitBalance/commit/180947dce58ebc3086b83f83ed4cb770b1466136))


### Bug Fixes

* include commit sha in PR preview version string ([#51](https://github.com/allapcallapc/SplitBalance/issues/51)) ([23091fd](https://github.com/allapcallapc/SplitBalance/commit/23091fdd7ba61092e03cbe1a0193b2e8d9b43b4a))
* replace summary table with compact proportional-bar ledger ([7cd1df4](https://github.com/allapcallapc/SplitBalance/commit/7cd1df4f9c874be5cb97d5dd4a8c107c88a03986))
* stop card panels from resizing when switching to dark theme ([#46](https://github.com/allapcallapc/SplitBalance/issues/46)) ([96a0666](https://github.com/allapcallapc/SplitBalance/commit/96a066682ab41d522b7168fa9527658ec6aa2fd0)), closes [#26](https://github.com/allapcallapc/SplitBalance/issues/26)

## [2.1.1](https://github.com/allapcallapc/SplitBalance/compare/v2.1.0...v2.1.1) (2026-08-05)


### Bug Fixes

* detect Google Wallet tap-to-pay notifications without a payment keyword ([#42](https://github.com/allapcallapc/SplitBalance/issues/42)) ([e9aeaa0](https://github.com/allapcallapc/SplitBalance/commit/e9aeaa0f9dc6df03d79d3235d404748b68dafa81))

## [2.1.0](https://github.com/allapcallapc/SplitBalance/compare/v2.0.10...v2.1.0) (2026-08-05)


### Features

* show missing percentage in period warning tooltip ([3b6ef2f](https://github.com/allapcallapc/SplitBalance/commit/3b6ef2f21a1abc6bbacd446f94f28ef3466610ae))
* show missing percentage in period warning tooltip ([b15b3fb](https://github.com/allapcallapc/SplitBalance/commit/b15b3fb76f7f7df1580780515a9809a099cd9228))


### Bug Fixes

* stop release-apk's push trigger from double-running itself ([5a9563b](https://github.com/allapcallapc/SplitBalance/commit/5a9563b68dad1166165bce67ced1d138e8277ef4))
* stop release-apk's push trigger from double-running itself ([d449241](https://github.com/allapcallapc/SplitBalance/commit/d449241046d21da2b8e0c0b2cf37f191e0a6c1aa))

## [2.0.10](https://github.com/allapcallapc/SplitBalance/compare/v2.0.9...v2.0.10) (2026-08-05)


### Bug Fixes

* correct category balance totals and prevent APK download sink leak ([952b28b](https://github.com/allapcallapc/SplitBalance/commit/952b28b86d40b86c286c5f36b51401a2d2d16f14))
* correct category balance totals and prevent APK download sink leak ([73e395d](https://github.com/allapcallapc/SplitBalance/commit/73e395d10f13191c8fbaf568f41df17f2156f72d))
