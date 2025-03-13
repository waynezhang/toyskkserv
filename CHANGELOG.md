## 1.0.0 (2025-03-13)

### Refactor

- deprecate zon_get_fields in favor of zig native zon parser ([057ff2a](https://github.com/waynezhang/toyskkserv/commit/057ff2aa2d641f3c75070ad2e0d5f3e6f5ae9cfd))
- migrate back to jdz_allocator to reduce memory usage ([a15c8d1](https://github.com/waynezhang/toyskkserv/commit/a15c8d11c233d99270fd08d78557f11017e43cba))
- minor change ([1b83ca0](https://github.com/waynezhang/toyskkserv/commit/1b83ca0ac6d4cc9b9c62431ab8cab9a7504162d9))


## 0.0.9 (2025-03-09)

### New feature

- ipv6 support ([a0ac94f](https://github.com/waynezhang/toyskkserv/commit/a0ac94ff4a88f675284ea1b75b9d6309626cdf05))

### Fix

- reload doesn't work with ipv6 address ([fccf6ff](https://github.com/waynezhang/toyskkserv/commit/fccf6ff808f96f2502f91efedbb4a4ac78de3425))

### Refactor

- don't store allocator ([1bb008e](https://github.com/waynezhang/toyskkserv/commit/1bb008e7693ba23deacaddd1363b4d3426df21ff))
- migrate to parg ([f322faf](https://github.com/waynezhang/toyskkserv/commit/f322faf17c06c0f0809c3f179a5b6bbae074b0c8))
- minor change ([66f45a6](https://github.com/waynezhang/toyskkserv/commit/66f45a6696e4f7c3437be866278557a5ae8d2ea9))
- remove dependency of percentage encode ([12ae1e7](https://github.com/waynezhang/toyskkserv/commit/12ae1e75bd765b8e0c02eb4f356550b57cd73ea4))
- remove some utils funcs ([0ab5d61](https://github.com/waynezhang/toyskkserv/commit/0ab5d611e74447a9f27e0b8dc9edf6581b5a4d0b))
- rename some funcs ([81d408f](https://github.com/waynezhang/toyskkserv/commit/81d408fe4f324069d7060ba8afa3e7a1e67a70ad))


## 0.0.8 (2025-02-22)

### New feature

- optimize memory usage ([9b13ba5](https://github.com/waynezhang/toyskkserv/commit/9b13ba5ddeb47032a2b2a22756a2734aa59922cf))
- reduce memory usage ([24b0944](https://github.com/waynezhang/toyskkserv/commit/24b0944f8c005ca3ff216a190353961749d068b9))

### Fix

- deinitialize properly ([0739339](https://github.com/waynezhang/toyskkserv/commit/0739339a2305ca91d277346b7f019fbadd20967f))
- unittest ([d32e4ff](https://github.com/waynezhang/toyskkserv/commit/d32e4ff2b6d41d3a4ce686893d0991ed99a081cb))

### Refactor

- download logic ([a6473f8](https://github.com/waynezhang/toyskkserv/commit/a6473f8372eeab6e1543875a598cbb7130c7437d))
- flatten structs ([8c79e1a](https://github.com/waynezhang/toyskkserv/commit/8c79e1a9639e526da20698240c0f5f7ce71bb7f0))
- rename DictLocation to Location ([cd173ac](https://github.com/waynezhang/toyskkserv/commit/cd173acda41486d6375985d6d43d7f44710adf29))


## v0.0.7 (2025-02-15)

### New feature

- show download progress. colorize logs ([f6a9fef](https://github.com/waynezhang/toyskkserv/commit/f6a9fef9e0c355a0137afd150ada1780f0a01f5f))
- support .tar.gz and .gz download ([ceea9cf](https://github.com/waynezhang/toyskkserv/commit/ceea9cf4e98585964bb1ce9076b44fc743b644be))

### Fix

- disable test for downloadFiles temparaly ([f93ce0b](https://github.com/waynezhang/toyskkserv/commit/f93ce0b08bc7ae977927640e9dcebfd91ebce473))

### Refactor

- remove version command as it shows in help command ([cce30d1](https://github.com/waynezhang/toyskkserv/commit/cce30d18b77218383bc838132b42c56bfd8a8420))
- small fixes ([d4fad0e](https://github.com/waynezhang/toyskkserv/commit/d4fad0e31e936742b4d299931bc2d48e44be1891))


## 0.0.6 (2025-02-12)

### Fix

- suppress memory usage by passing allocator to handlers ([e433cfc](https://github.com/waynezhang/toyskkserv/commit/e433cfc108d75704d76fccf70e1834fba878cb2f))


## v0.0.5 (2025-02-11)

### New feature

- reload command ([3f67678](https://github.com/waynezhang/toyskkserv/commit/3f67678048d5fefe5e8f5af4dacff62ee0784650))
- update command ([0fb4ce5](https://github.com/waynezhang/toyskkserv/commit/0fb4ce5301623fdaa8f2118ee5f2acee306ffae8))

### Fix

- (workaround) disable log from zon_get_field ([bb9b254](https://github.com/waynezhang/toyskkserv/commit/bb9b254f3e83db3a6bc1758f9bed749dba6eae64))
- leak ([6c9e961](https://github.com/waynezhang/toyskkserv/commit/6c9e96129fd2375e44cacc1034a7383d17d28353))
- log ([ae1cece](https://github.com/waynezhang/toyskkserv/commit/ae1ceced3feab282d2ada678196af3d1483b5ad3))

### Refactor

- build.zig ([3ea5e6f](https://github.com/waynezhang/toyskkserv/commit/3ea5e6f264deb5aaf91a490f173b97755762ea6d))
- move cmds to cmd directory ([89aaff5](https://github.com/waynezhang/toyskkserv/commit/89aaff5742d8c8f184e2e85f4465fc0413eedaf4))
- orgnaize files ([5079abe](https://github.com/waynezhang/toyskkserv/commit/5079abef2241cbc8cc33e176e32b9b43a9b9b877))
- separate euc-jis-2004 converter ([2583424](https://github.com/waynezhang/toyskkserv/commit/2583424c3a245ad6bb085774c81655f0c39df96a))
- separate skk dict parse logic ([64793c3](https://github.com/waynezhang/toyskkserv/commit/64793c37823d9a6630c55e9a3939f4e7a64a0470))


## v0.0.4 (2025-02-09)

### Fix

- config file is not found ([bef6d29](https://github.com/waynezhang/toyskkserv/commit/bef6d29a097c5c5f1794a7f89e7a3b397e77ff08))
- download and load didctionary in relative path ([4b72111](https://github.com/waynezhang/toyskkserv/commit/4b72111a68730697c00e3b48cd8b6a1f0ea387ec))


## v0.0.3 (2025-02-09)

### Fix

- config file is not found ([bef6d29](https://github.com/waynezhang/toyskkserv/commit/bef6d29a097c5c5f1794a7f89e7a3b397e77ff08))


## v0.0.2 (2025-02-09)

### New feature

- dynamic version ([21d9175](https://github.com/waynezhang/toyskkserv/commit/21d91757bd2802564b21b1a2b479f9d568164b3b))
- first commit ([78b8c47](https://github.com/waynezhang/toyskkserv/commit/78b8c47f8734f5147340d4a43005f27018513204))
- reload command, replace allocator to jdz to save memory and ensure thread-safety ([fdca680](https://github.com/waynezhang/toyskkserv/commit/fdca680ca75f3bedcfe3cfd78103da00430f62a7))
- verbose mode ([01c9bd3](https://github.com/waynezhang/toyskkserv/commit/01c9bd330d9a650c6943f7838b1fb502d82e4ce7))

### Fix

- crash on disconnection ([ca8a06a](https://github.com/waynezhang/toyskkserv/commit/ca8a06a6ecbf6b38bd9ac9f49debc7ae9038eb0c))
- crash on downloading file ([0237ebc](https://github.com/waynezhang/toyskkserv/commit/0237ebc06abb57d2d2b0af3a8056704e361ac971))
- crash on empty request ([7c2d4c2](https://github.com/waynezhang/toyskkserv/commit/7c2d4c2fc985d1c17d437d70cffcd1836e8ea1d2))

### Refactor

- log ([ad4722e](https://github.com/waynezhang/toyskkserv/commit/ad4722e8c4fe1b12b72648d2031e305ec94ac1ed))
- migrate to single threaded ([7cf8ff3](https://github.com/waynezhang/toyskkserv/commit/7cf8ff364c649d2305541f215b5c7f9318c48efe))
- split download from dict ([7819093](https://github.com/waynezhang/toyskkserv/commit/78190936558c008ab4e9964fb1b3b154875c025f))


## v0.0.1 (2025-02-09)

- Initial commit
