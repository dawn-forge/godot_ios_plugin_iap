# StoreKit source provenance

This repository is a Dawn Forge fork of `hrk4649/godot_ios_plugin_iap`.

- Upstream repository: https://github.com/hrk4649/godot_ios_plugin_iap
- Approved fork: https://github.com/dawn-forge/godot_ios_plugin_iap
- Immutable upstream pin: `f5b3747efb066c00ea3e206ff9b4f732ade5ed37`
- Fork branch: `dawnforge/deferred-finish`
- License: MIT, retained verbatim in `LICENSE`
- Native contract: StoreKit 2 verified transactions remain unfinished until
  `request("finishTransaction", {"transactionID": ...})` succeeds.

The fork does not vendor or derive from Sudoku's XCFramework. The upstream pin
identifies the reviewed StoreKit source lineage; it is not the compiled fork
commit. A release archive must also record its exact clean Dawn Forge fork
`build_commit` and matching annotated `build_tag`, with the documented Godot
and Xcode toolchain.
