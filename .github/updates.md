# Build and update checks

Push a `v*` tag to run checks and publish an install ZIP with the BigWigs packager. The packager replaces the TOC's `@project-version@` with the tag version and puts the addon directly inside the `BetterForeverCooldowns` folder. Tags containing `beta` create preview releases. Keep `addon_version` in `.github/wow-version.json` in sync when releasing a manual version bump.

`Forever update` checks Blizzard's live wowf endpoint hourly, or on a manual run or `wow-updated` repository dispatch. A new build on the known game patch stages an addon patch-version bump. Lua 5.1 syntax checks and automation regression tests must pass before the workflow commits, tags, and packages the update. Failures open a deduplicated GitHub issue with workflow logs; unchanged builds stay quiet.

The initial game checkpoint and verified Interface are copied from FriendlyNameplateGuild. `runtime_ready: false` keeps automatic releases in beta form. Syntax checks and automation tests do not verify gameplay or live API compatibility; set this flag to true only after verifying the addon in-game.

An unfamiliar game patch blocks publication until its Interface is verified. Blizzard's version table does not provide Interface, so it is never inferred from the build. Set the optional `FOREVER_BUILD_FEED_URL` repository variable to an HTTPS JSON feed containing `product: wowf`, `channel: live`, and the exact official live `build` and verified `interface`, or update the checkpoint in a reviewed commit after checking in-game.

Both workflows use the same checks. The scheduled workflow packages directly after pushing its tag because pushes using `GITHUB_TOKEN` do not trigger the tag workflow. A push race or release failure opens an issue; if upload fails after the tag was pushed, rerun Build for that tag. GitHub schedules may be delayed or disabled after inactivity. The addon itself never downloads updates.

Run automation tests locally with `bash .github/tests/update.sh` (Bash and jq required). GitHub also parses both addon Lua files with Lua 5.1. Development files and the existing local ZIP are excluded from release packages.
