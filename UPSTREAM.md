# StoreKit source provenance

This repository is a Dawn Forge fork of `hrk4649/godot_ios_plugin_iap`.

- Upstream repository: https://github.com/hrk4649/godot_ios_plugin_iap
- Approved fork: https://github.com/dawn-forge/godot_ios_plugin_iap
- Source commit: `f5b3747efb066c00ea3e206ff9b4f732ade5ed37`
- Fork branch: `dawnforge/deferred-finish`
- License: MIT, retained verbatim in `LICENSE`
- Native contract: StoreKit 2 verified transactions remain unfinished until
  `request("finishTransaction", {"transactionID": ...})` succeeds.

The fork does not vendor or derive from Sudoku's XCFramework. Release archives
must be built from this commit with the documented Godot and Xcode toolchain.
