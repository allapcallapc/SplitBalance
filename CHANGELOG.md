# Changelog

## [3.1.0](https://github.com/allapcallapc/SplitBalance/compare/v3.0.0...v3.1.0) (2026-08-08)


### Features

* add sort control to the bills screen ([#48](https://github.com/allapcallapc/SplitBalance/issues/48)) ([ccebd2d](https://github.com/allapcallapc/SplitBalance/commit/ccebd2dd8eefca8fd3397dfa42f6e117bf2ee570))
* move summary balance calculation to narrow aggregated queries ([#55](https://github.com/allapcallapc/SplitBalance/issues/55)) ([0204404](https://github.com/allapcallapc/SplitBalance/commit/0204404d54efdc0a436961b97370c3c8af030f9d))
* show per-person expense counts in Summary Statistics card ([#45](https://github.com/allapcallapc/SplitBalance/issues/45)) ([4d5fc43](https://github.com/allapcallapc/SplitBalance/commit/4d5fc431d931242873d8a16344d0f745be6bf625))


### Bug Fixes

* aggregate person/household bill totals server-side via Postgres RPCs ([#58](https://github.com/allapcallapc/SplitBalance/issues/58)) ([1f1bc10](https://github.com/allapcallapc/SplitBalance/commit/1f1bc10c7cb172c83663eebc4a2cf57bcd9afebf))

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
