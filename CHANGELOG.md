# Changelog

## Unreleased

### Added

* Pretty table output format using `table_tennis` gem
* `--format pretty` option for CLI list command
* Enhanced table rendering with borders and zebra striping
* Configuration validation for output_format setting

### Changed

* Updated `tty-progressbar` dependency to support `table_tennis`

## [0.1.4](https://github.com/damacus/github-cookstyle-runner/compare/github-cookstyle-runner/v0.1.3...github-cookstyle-runner/v0.1.4) (2025-12-13)


### Code Refactoring

* Extract SemanticLogger regex constant and document config logging rationale ([#164](https://github.com/damacus/github-cookstyle-runner/issues/164)) ([6768a2b](https://github.com/damacus/github-cookstyle-runner/commit/6768a2b8b888807cda8f15abd62e95264ddd1fda))

## [0.1.3](https://github.com/damacus/github-cookstyle-runner/compare/github-cookstyle-runner/v0.1.2...github-cookstyle-runner/v0.1.3) (2025-11-29)


### Chores

* **ci:** source renovate-config for auto-merging GitHub Actions ([#159](https://github.com/damacus/github-cookstyle-runner/issues/159)) ([016324c](https://github.com/damacus/github-cookstyle-runner/commit/016324c814babe41e0eb62f42d26e56727d63d52))
* **deps:** update actions/checkout action to v6 ([#158](https://github.com/damacus/github-cookstyle-runner/issues/158)) ([2fd9df9](https://github.com/damacus/github-cookstyle-runner/commit/2fd9df92af2db9d96efc1d151c0acddc6c23a988))
* **deps:** update actions/upload-artifact action to v5 ([#135](https://github.com/damacus/github-cookstyle-runner/issues/135)) ([120a62f](https://github.com/damacus/github-cookstyle-runner/commit/120a62f6fff5f747d036c3e0cd769e94ec7cf1e4))
* **deps:** update dependency cookstyle to v8.5.2 ([#139](https://github.com/damacus/github-cookstyle-runner/issues/139)) ([b4707f8](https://github.com/damacus/github-cookstyle-runner/commit/b4707f81ca889158d435389e20297083dd0f514c))
* **deps:** update dependency git to v4.0.6 ([#153](https://github.com/damacus/github-cookstyle-runner/issues/153)) ([d13fb4d](https://github.com/damacus/github-cookstyle-runner/commit/d13fb4dfea74a4600875b983e97e099dbae18883))
* **deps:** update dependency json to v2.15.2 ([#136](https://github.com/damacus/github-cookstyle-runner/issues/136)) ([1e3d372](https://github.com/damacus/github-cookstyle-runner/commit/1e3d372f7020039e900dab0c1ebef456424611e5))
* **deps:** update dependency json to v2.16.0 ([#152](https://github.com/damacus/github-cookstyle-runner/issues/152)) ([92e1397](https://github.com/damacus/github-cookstyle-runner/commit/92e139724de16e4f36423f0d205740b86481ded5))
* **deps:** update dependency rspec to v3.13.2 ([#130](https://github.com/damacus/github-cookstyle-runner/issues/130)) ([b0abffe](https://github.com/damacus/github-cookstyle-runner/commit/b0abffe50af308f7a26abf737ff82205471abdc2))
* **deps:** update dependency rubocop to v1.81.6 ([#137](https://github.com/damacus/github-cookstyle-runner/issues/137)) ([421204c](https://github.com/damacus/github-cookstyle-runner/commit/421204c8426a5a4ad5fdeca8a3dc1f13676edc23))
* **deps:** update dependency rubocop-rspec to v3.8.0 ([#154](https://github.com/damacus/github-cookstyle-runner/issues/154)) ([0569bda](https://github.com/damacus/github-cookstyle-runner/commit/0569bda2cb273e9b233691ba92d0730568409411))
* **deps:** update dependency sorbet to v0.6.12650 ([#124](https://github.com/damacus/github-cookstyle-runner/issues/124)) ([81f5c99](https://github.com/damacus/github-cookstyle-runner/commit/81f5c99260267912aadbee94c23f11c78d31e13b))
* **deps:** update dependency sorbet to v0.6.12683 ([#131](https://github.com/damacus/github-cookstyle-runner/issues/131)) ([754ed96](https://github.com/damacus/github-cookstyle-runner/commit/754ed96e1a0da764848e46cea76c1c3dc345159b))
* **deps:** update dependency sorbet to v0.6.12783 ([#146](https://github.com/damacus/github-cookstyle-runner/issues/146)) ([b0a6a51](https://github.com/damacus/github-cookstyle-runner/commit/b0a6a5158b9d35e1351dffde9b44a773c95c0f30))
* **deps:** update dependency sorbet-runtime to v0.6.12650 ([#125](https://github.com/damacus/github-cookstyle-runner/issues/125)) ([c7599e9](https://github.com/damacus/github-cookstyle-runner/commit/c7599e92df3d0798aa945e98ae2e1acdcbc695f9))
* **deps:** update dependency sorbet-runtime to v0.6.12683 ([#132](https://github.com/damacus/github-cookstyle-runner/issues/132)) ([a8cba8a](https://github.com/damacus/github-cookstyle-runner/commit/a8cba8a1b5cd3dfc7338cd6e6693bcdcbbbcd946))
* **deps:** update dependency tapioca to v0.17.7 ([#126](https://github.com/damacus/github-cookstyle-runner/issues/126)) ([e874928](https://github.com/damacus/github-cookstyle-runner/commit/e87492868214043f315dac2b597c2b1b4ca816bc))
* **deps:** update dependency tapioca to v0.17.8 ([#128](https://github.com/damacus/github-cookstyle-runner/issues/128)) ([66883ea](https://github.com/damacus/github-cookstyle-runner/commit/66883eaee93c2d551f3c0bda77a99762192256bb))
* **deps:** update dependency tapioca to v0.17.8 ([#133](https://github.com/damacus/github-cookstyle-runner/issues/133)) ([0201e74](https://github.com/damacus/github-cookstyle-runner/commit/0201e743feabafba987db42a28e68af7c09f3dd1))
* **deps:** update dependency tapioca to v0.17.9 ([#140](https://github.com/damacus/github-cookstyle-runner/issues/140)) ([47b4415](https://github.com/damacus/github-cookstyle-runner/commit/47b44150ea59430d22c98d48d002389a98c8ba0d))
* **deps:** update dependency webmock to v3.26.1 ([#138](https://github.com/damacus/github-cookstyle-runner/issues/138)) ([b0d6d35](https://github.com/damacus/github-cookstyle-runner/commit/b0d6d3527a3e994d49e8e4be3fd76e3130eeb460))
* **deps:** update docker/metadata-action digest to 318604b ([#149](https://github.com/damacus/github-cookstyle-runner/issues/149)) ([d2ca3e7](https://github.com/damacus/github-cookstyle-runner/commit/d2ca3e74c123e4220da62c7ffec2efb015ae663c))
* **deps:** update docker/setup-qemu-action digest to c7c5346 ([#151](https://github.com/damacus/github-cookstyle-runner/issues/151)) ([a96702a](https://github.com/damacus/github-cookstyle-runner/commit/a96702ab28d576965f8bc5a41ea0a7d8b08e88c7))
* **deps:** update googleapis/release-please-action digest to 16a9c90 ([#134](https://github.com/damacus/github-cookstyle-runner/issues/134)) ([50584c2](https://github.com/damacus/github-cookstyle-runner/commit/50584c224e58d2e1db6a3657708705f20caa81b5))
* **deps:** update ruby:3.4-slim docker digest to c1734f5 ([#129](https://github.com/damacus/github-cookstyle-runner/issues/129)) ([91a1195](https://github.com/damacus/github-cookstyle-runner/commit/91a119575ec032dfb6422f407f33478e3cf30dfa))
* **deps:** update ruby:3.4-slim docker digest to c1bc8f6 ([#148](https://github.com/damacus/github-cookstyle-runner/issues/148)) ([b515299](https://github.com/damacus/github-cookstyle-runner/commit/b5152996d66ab04621e59933f18f57a4562ea798))


### Bug Fixes

* Add automatic Copilot agent assignment for manual fix issues ([#142](https://github.com/damacus/github-cookstyle-runner/issues/142)) ([f4ad5af](https://github.com/damacus/github-cookstyle-runner/commit/f4ad5afb32fb2e1151a5049b9976bb2997766e89))
* duplicate YAML key in .markdownlint-cli2.yaml ([#150](https://github.com/damacus/github-cookstyle-runner/issues/150)) ([02d2d8c](https://github.com/damacus/github-cookstyle-runner/commit/02d2d8c2741e4428cffb3153deccc184332a6817))
* Relax markdown linting configuration ([#144](https://github.com/damacus/github-cookstyle-runner/issues/144)) ([40260a5](https://github.com/damacus/github-cookstyle-runner/commit/40260a57509d4def323ae71f2abc095c37d0658c))


### Code Refactoring

* Extract common GitHub operations into reusable helpers ([#157](https://github.com/damacus/github-cookstyle-runner/issues/157)) ([831ed93](https://github.com/damacus/github-cookstyle-runner/commit/831ed9315a3779ab249462ef22f50b870737c4f2))

## [0.1.2](https://github.com/damacus/github-cookstyle-runner/compare/github-cookstyle-runner/v0.1.1...github-cookstyle-runner/v0.1.2) (2025-10-13)


### Chores

* **deps:** update dependency rubocop to v1.81.1 ([#110](https://github.com/damacus/github-cookstyle-runner/issues/110)) ([c3fc29b](https://github.com/damacus/github-cookstyle-runner/commit/c3fc29b786865c9771e515b4485b1048bc03abbc))
* **deps:** update dependency ruby to v3.4.7 ([#114](https://github.com/damacus/github-cookstyle-runner/issues/114)) ([43f2656](https://github.com/damacus/github-cookstyle-runner/commit/43f26565e4e658e5dbdf605ef523a3d800a4e438))
* **deps:** update dependency sorbet to v0.6.12638 ([#113](https://github.com/damacus/github-cookstyle-runner/issues/113)) ([c098a1a](https://github.com/damacus/github-cookstyle-runner/commit/c098a1a909a97a29bbead80ed06f7ea01fe408fc))
* **deps:** update dependency sorbet-runtime to v0.6.12638 ([#112](https://github.com/damacus/github-cookstyle-runner/issues/112)) ([397b9e5](https://github.com/damacus/github-cookstyle-runner/commit/397b9e5f3eff5f9639f1cf2025dbf93bc51b9403))
* **deps:** update dependency tapioca to v0.17.7 ([#111](https://github.com/damacus/github-cookstyle-runner/issues/111)) ([e515030](https://github.com/damacus/github-cookstyle-runner/commit/e515030eafacb2feb3c74698c9d0bd495196727b))


### Features

* add clean-prs command and fix configuration loading ([5012148](https://github.com/damacus/github-cookstyle-runner/commit/5012148cbb4c79b69091de8e64bfba0ad5ff304b))


### Bug Fixes

* **logging:** Update logging output ([#121](https://github.com/damacus/github-cookstyle-runner/issues/121)) ([41e060d](https://github.com/damacus/github-cookstyle-runner/commit/41e060d91fec3a940aab0fdb684c05b3e931c07e))


### Code Refactoring

* fix unreachable guard clause in repository processor ([#123](https://github.com/damacus/github-cookstyle-runner/issues/123)) ([0cb683a](https://github.com/damacus/github-cookstyle-runner/commit/0cb683a7bfc5a1c84201d6fb2f1b8b7b778d476b))

## [0.1.1](https://github.com/damacus/github-cookstyle-runner/compare/github-cookstyle-runner-v0.1.0...github-cookstyle-runner/v0.1.1) (2025-10-09)

### Chores

* CLI improvements and Lefthook integration ([#79](https://github.com/damacus/github-cookstyle-runner/issues/79)) ([f75bf3e](https://github.com/damacus/github-cookstyle-runner/commit/f75bf3edc674701a3c1d909d7b44d84d003c785a))
* **deps:** add renovate.json ([3c9a7e0](https://github.com/damacus/github-cookstyle-runner/commit/3c9a7e03b999ac0489fba626542d7331e39d2e5c))
* **deps:** pin actions/cache action to 0057852 ([#86](https://github.com/damacus/github-cookstyle-runner/issues/86)) ([8f58755](https://github.com/damacus/github-cookstyle-runner/commit/8f5875552c28f6ee5a0cfc1b5436ab805db2e743))
* **deps:** pin dependencies ([432d3da](https://github.com/damacus/github-cookstyle-runner/commit/432d3da23d6c8efc5ed4707d10e59e24a60bf894))
* **deps:** pin dependencies ([#32](https://github.com/damacus/github-cookstyle-runner/issues/32)) ([13c1e33](https://github.com/damacus/github-cookstyle-runner/commit/13c1e336018a06808dbefc94a31257166e8cc7fb))
* **deps:** pin dependencies ([#34](https://github.com/damacus/github-cookstyle-runner/issues/34)) ([7dc3592](https://github.com/damacus/github-cookstyle-runner/commit/7dc359238cf203addb745e9136d1bf00e19cc16d))
* **deps:** pin dependencies ([#35](https://github.com/damacus/github-cookstyle-runner/issues/35)) ([d590963](https://github.com/damacus/github-cookstyle-runner/commit/d590963c9341bc17854ac0a43cb8e613050c2bba))
* **deps:** pin dependencies ([#70](https://github.com/damacus/github-cookstyle-runner/issues/70)) ([eb6fa20](https://github.com/damacus/github-cookstyle-runner/commit/eb6fa2068f4b3e28ea8771f78af816f0175be9f1))
* **deps:** update actions/checkout action to v5 ([#56](https://github.com/damacus/github-cookstyle-runner/issues/56)) ([4eb77d9](https://github.com/damacus/github-cookstyle-runner/commit/4eb77d90fda9d91925e785a80857ac91faaa33b7))
* **deps:** update actions/checkout action to v5 ([#71](https://github.com/damacus/github-cookstyle-runner/issues/71)) ([9fc05f5](https://github.com/damacus/github-cookstyle-runner/commit/9fc05f5bd060e4af14946673072f8e1a36f5bc9e))
* **deps:** update actions/setup-python action to v6 ([#87](https://github.com/damacus/github-cookstyle-runner/issues/87)) ([2f63f0d](https://github.com/damacus/github-cookstyle-runner/commit/2f63f0d0afe6131ee356371ee7f2e9996f8b609a))
* **deps:** update davidanson/markdownlint-cli2-action action to v20 ([432c6f7](https://github.com/damacus/github-cookstyle-runner/commit/432c6f709e46381b51b3ab38751a3646ccfc5b2c))
* **deps:** update dependency config to v5.6.1 ([#50](https://github.com/damacus/github-cookstyle-runner/issues/50)) ([98df4b0](https://github.com/damacus/github-cookstyle-runner/commit/98df4b06b2e2d810edcd59075ec763c6082db7b9))
* **deps:** update dependency fakefs to v3.0.1 ([#54](https://github.com/damacus/github-cookstyle-runner/issues/54)) ([a43f767](https://github.com/damacus/github-cookstyle-runner/commit/a43f7675e669c6d93941ca0c4a78712cdaadcf78))
* **deps:** update dependency git to v4 ([#49](https://github.com/damacus/github-cookstyle-runner/issues/49)) ([7e1d09e](https://github.com/damacus/github-cookstyle-runner/commit/7e1d09e14cc65586200e2e566652dd08e5de2290))
* **deps:** update dependency jwt to v3 ([#72](https://github.com/damacus/github-cookstyle-runner/issues/72)) ([a993d7d](https://github.com/damacus/github-cookstyle-runner/commit/a993d7df91e04b7dffad4a6cf9cc50f63331ca47))
* **deps:** update dependency octokit to v10 ([#73](https://github.com/damacus/github-cookstyle-runner/issues/73)) ([bbb51db](https://github.com/damacus/github-cookstyle-runner/commit/bbb51dbebc64dc8d5b4397f03bfaa368b06686f9))
* **deps:** update dependency pp to v0.6.3 ([#81](https://github.com/damacus/github-cookstyle-runner/issues/81)) ([8b138c8](https://github.com/damacus/github-cookstyle-runner/commit/8b138c85c39c104be4ed255551d6c7a27e786a9d))
* **deps:** update dependency rubocop to v1.81.1 ([#40](https://github.com/damacus/github-cookstyle-runner/issues/40)) ([d349d89](https://github.com/damacus/github-cookstyle-runner/commit/d349d89574f0e85f971505bab8649df9e5d783e6))
* **deps:** update dependency rubocop-performance to v1.26.0 ([#64](https://github.com/damacus/github-cookstyle-runner/issues/64)) ([d171cd8](https://github.com/damacus/github-cookstyle-runner/commit/d171cd837071f504c50cfd37bc25f7c10d975e48))
* **deps:** update dependency rubocop-rspec to v3.7.0 ([#63](https://github.com/damacus/github-cookstyle-runner/issues/63)) ([baf7103](https://github.com/damacus/github-cookstyle-runner/commit/baf71038d54adebd390e9d38acafbf72d625f65d))
* **deps:** update dependency ruby to v3.4.6 ([#51](https://github.com/damacus/github-cookstyle-runner/issues/51)) ([75fc27a](https://github.com/damacus/github-cookstyle-runner/commit/75fc27a2fd823e3800429f603dafc741744f1de1))
* **deps:** update dependency ruby to v3.4.7 ([#93](https://github.com/damacus/github-cookstyle-runner/issues/93)) ([67cc4e8](https://github.com/damacus/github-cookstyle-runner/commit/67cc4e8d79f0e6333cc0a04fd07a90dc4e9e0689))
* **deps:** update dependency sorbet to v0.5.12435 ([#37](https://github.com/damacus/github-cookstyle-runner/issues/37)) ([d2448e7](https://github.com/damacus/github-cookstyle-runner/commit/d2448e7c982894ce0c38c0a1b24146cef3c7da3a))
* **deps:** update dependency sorbet to v0.6.12627 ([#61](https://github.com/damacus/github-cookstyle-runner/issues/61)) ([946f6e8](https://github.com/damacus/github-cookstyle-runner/commit/946f6e876542eda0f796f0de59d6a9cd3a3e9331))
* **deps:** update dependency sorbet to v0.6.12632 ([#96](https://github.com/damacus/github-cookstyle-runner/issues/96)) ([9f8966c](https://github.com/damacus/github-cookstyle-runner/commit/9f8966c4b69259d5f1bbea84e01d8a1094eaa735))
* **deps:** update dependency sorbet-runtime to v0.5.12435 ([#38](https://github.com/damacus/github-cookstyle-runner/issues/38)) ([e73ae4e](https://github.com/damacus/github-cookstyle-runner/commit/e73ae4e458474c6f74f95288485c77a3b23693d7))
* **deps:** update dependency sorbet-runtime to v0.6.12565 ([#62](https://github.com/damacus/github-cookstyle-runner/issues/62)) ([734a781](https://github.com/damacus/github-cookstyle-runner/commit/734a781303551a6a3430415628ec183f00f254a3))
* **deps:** update dependency sorbet-runtime to v0.6.12627 ([#65](https://github.com/damacus/github-cookstyle-runner/issues/65)) ([6d49652](https://github.com/damacus/github-cookstyle-runner/commit/6d49652ac62121dcfeebd93a4bbd5f17cf393861))
* **deps:** update dependency sorbet-runtime to v0.6.12632 ([#97](https://github.com/damacus/github-cookstyle-runner/issues/97)) ([44e87d4](https://github.com/damacus/github-cookstyle-runner/commit/44e87d48ec3df53f337c6f026fe287d2c9e3c9b3))
* **deps:** update dependency tapioca to v0.17.7 ([#101](https://github.com/damacus/github-cookstyle-runner/issues/101)) ([6e19719](https://github.com/damacus/github-cookstyle-runner/commit/6e19719c9e61a4855d63d234a885a4734b6444d0))
* **deps:** update dependency tapioca to v0.17.7 ([#39](https://github.com/damacus/github-cookstyle-runner/issues/39)) ([2cf6215](https://github.com/damacus/github-cookstyle-runner/commit/2cf6215c9604a025d40571346f2cd54fc3ae99b3))
* **deps:** update dependency tapioca to v0.17.7 ([#59](https://github.com/damacus/github-cookstyle-runner/issues/59)) ([7f4f9e8](https://github.com/damacus/github-cookstyle-runner/commit/7f4f9e8a3898d66a7cbdf7120e796161d4e1500e))
* **deps:** update dependency tapioca to v0.17.7 ([#98](https://github.com/damacus/github-cookstyle-runner/issues/98)) ([381165a](https://github.com/damacus/github-cookstyle-runner/commit/381165a173abc4257e1e000dfee88bf1bfdd6428))
* **deps:** update docker/build-push-action action to v6 ([4b78a9a](https://github.com/damacus/github-cookstyle-runner/commit/4b78a9af1f69e7f2550f6ba946139414114b6e0f))
* **deps:** update docker/build-push-action action to v6 ([#31](https://github.com/damacus/github-cookstyle-runner/issues/31)) ([60775ae](https://github.com/damacus/github-cookstyle-runner/commit/60775aedda7a513d95388134526213235f5b976c))
* **deps:** update docker/build-push-action action to v6 ([#74](https://github.com/damacus/github-cookstyle-runner/issues/74)) ([7d8a8b2](https://github.com/damacus/github-cookstyle-runner/commit/7d8a8b2af2c4a2e356d1303508eb1f1eb5ca2627))
* **deps:** update docker/build-push-action digest to 2634353 ([#41](https://github.com/damacus/github-cookstyle-runner/issues/41)) ([caf8990](https://github.com/damacus/github-cookstyle-runner/commit/caf899008a520551b3fa97c561248c3fd68bd5af))
* **deps:** update docker/login-action digest to 184bdaa ([#52](https://github.com/damacus/github-cookstyle-runner/issues/52)) ([545476e](https://github.com/damacus/github-cookstyle-runner/commit/545476e253d8ac4f39a29438ad82cd01e9beab92))
* **deps:** update docker/login-action digest to 5e57cd1 ([#66](https://github.com/damacus/github-cookstyle-runner/issues/66)) ([1ab0041](https://github.com/damacus/github-cookstyle-runner/commit/1ab0041e261ed3a924f2fdd4d98c0f5f3eabcc11))
* **deps:** update docker/metadata-action digest to c1e5197 ([#53](https://github.com/damacus/github-cookstyle-runner/issues/53)) ([581caa9](https://github.com/damacus/github-cookstyle-runner/commit/581caa9fd0614c3d667d165f5b7f26b9e4d1c4d7))
* **deps:** update docker/setup-buildx-action digest to e468171 ([#47](https://github.com/damacus/github-cookstyle-runner/issues/47)) ([63607e3](https://github.com/damacus/github-cookstyle-runner/commit/63607e345c91169db069f4d9aaa29a83eec8abd1))
* **deps:** update ruby:3.4-slim docker digest to 39ab376 ([#99](https://github.com/damacus/github-cookstyle-runner/issues/99)) ([cf80869](https://github.com/damacus/github-cookstyle-runner/commit/cf80869712c8f301dd02fd73b401e0270e7a0cd8))
* **deps:** update softprops/action-gh-release digest to 6cbd405 ([#46](https://github.com/damacus/github-cookstyle-runner/issues/46)) ([d011e11](https://github.com/damacus/github-cookstyle-runner/commit/d011e11aeff8ab351956d109089cb818f65371dd))
* **deps:** update softprops/action-gh-release digest to aec2ec5 ([#91](https://github.com/damacus/github-cookstyle-runner/issues/91)) ([8878e48](https://github.com/damacus/github-cookstyle-runner/commit/8878e48e7d2a65e5c430ca06a3811d321090b0d8))

### Features

* Add extract_offenses method to CookstyleOperations ([#83](https://github.com/damacus/github-cookstyle-runner/issues/83)) ([76a1919](https://github.com/damacus/github-cookstyle-runner/commit/76a191933675b3536496cd01a4e0a6439b377488))
* add VCR and integration test infrastructure ([130e04b](https://github.com/damacus/github-cookstyle-runner/commit/130e04be650ee83191811a4b36fc46325031bf0a))
* implement comprehensive CLI with TTY framework ([#77](https://github.com/damacus/github-cookstyle-runner/issues/77)) ([5441642](https://github.com/damacus/github-cookstyle-runner/commit/5441642e898b412eb7e87b77a111715975d18cd8))
* implement Runner class for executing Cookstyle on repositories ([2645369](https://github.com/damacus/github-cookstyle-runner/commit/2645369f70853d0d5b2fb9c379767cd48f5e4b03))

### Bug Fixes

* Add instructions ([#76](https://github.com/damacus/github-cookstyle-runner/issues/76)) ([5a00880](https://github.com/damacus/github-cookstyle-runner/commit/5a00880644a3268f894152e439877a35218e4d68)), closes [#58](https://github.com/damacus/github-cookstyle-runner/issues/58)
* **docs:** Update docs ([#100](https://github.com/damacus/github-cookstyle-runner/issues/100)) ([b247235](https://github.com/damacus/github-cookstyle-runner/commit/b247235519a04908b77affdfcdb8d4c2ea19c325))
* **removate:** Update renovate config templates ([#103](https://github.com/damacus/github-cookstyle-runner/issues/103)) ([6d61376](https://github.com/damacus/github-cookstyle-runner/commit/6d61376789a7622dc39305206cf0e433d0239366))
* Remove changelog management ([#75](https://github.com/damacus/github-cookstyle-runner/issues/75)) ([97abbf4](https://github.com/damacus/github-cookstyle-runner/commit/97abbf4150d542eef99084243272ea95d8f4897d))
* **tapioca:** Update types ([#95](https://github.com/damacus/github-cookstyle-runner/issues/95)) ([635d1cd](https://github.com/damacus/github-cookstyle-runner/commit/635d1cddbeef62c27563db83521c25bbff599c3b))

### Code Refactoring

* Complete rewrite from PowerShell to Ruby with comprehensive test coverage ([#67](https://github.com/damacus/github-cookstyle-runner/issues/67)) ([55ba2c0](https://github.com/damacus/github-cookstyle-runner/commit/55ba2c00e74274a25ca0012bb52e033e5a30e31e))

## 2.0.0 - *2021-08-11*

* Breaking Change: Defaults to looking for main branches, introduces new cli arg for setting default branch name

## 1.4.3 - *2020-11-18*

* Removed branch cleanup workflow as now using github repo settings

## 1.4.2 - *2020-11-18*

* Fixed bug with dockerhub push due to set-env deprecation

## 1.4.1 - *2020-10-25*

* Resolved issues with pagination:
  * Set auth headers correctly
  * Removed duplicate results from being added

## 1.3.1

Stop `"` blowing up the builds

## 1.3.0

Remove Chef Workstation as cookstyle is not up to date there
Installs cookstyle manually

## 1.2.0

Removed user configurable pull request body
Pull request body now has the cookstyle version in it

## 1.1.1

Make change log marker case insensitive

## 1.0.0

Full initial release of the application with all functionality working
