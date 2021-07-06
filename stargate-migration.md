# Stargate migration

This document describe the steps needed in order to upgrade a validator node running on `fetchd v0.7.x` to the `fetchd TODO_FETCHD_LATEST_TAG`.
It is **advised to read the whole document before starting applying this procedure**, in order to avoid your validator node being unable to restart.
In case anything is unclear or if you have any questions, feel free to reach us out or ask in the Discord #validator channel.

## Before starting

### Get familiar with the new version

The stargate upgrade introduce many changes in the application, most notably, the `fetchcli` binary have disappeared, and all commands its can now be ran on `fetchd` directly. You can test this new version by following the install instructions for the `fetchd TODO_FETCHD_LATEST_TAG` and interact with our `stargateworld` testnet (get the connections settings on [our networks documentation page](https://docs.fetch.ai/ledger_v2/networks/)).


### Locate your files

Before starting, make sure to locate the following files on your validator host:

- **FETCHD_HOME**: folder containing all of the validator data. By default, the `fetchd` command will automatically create it under `~/.fetchd`, or in the location pointed by the `--home` flag on its first invocation if it doesn't exist.
- FETCHD_HOME/config/**node_key.json**: this file hold your node private key.
- FETCHD_HOME/config/**priv_validator_key.json**: this file hold your validator private key.
- FETCHD_HOME/config/**config.toml**: this is your node configuration
- FETCHD_HOME/config/**app.toml**: this configuration allows to tune the cosmos application, such as enabled apis, telemetry, pruning...
- FETCHD_HOME/config/**client.toml**: this file stores the client config, equivalent to the legacy `fetchcli config` which is now replaced by `fetchd config`.

> If needed, use the [./scripts/locate_home.sh](./scripts/locate_home.sh) script to help find the right folder, giving it your validator operator address and a search path:  
> ```
> ./scripts/locate_home.sh fetchvaloper1fvcepqdw4lcc4s0gmxxfhkptyasfceg69x9gsc /home/
> ```
> (if no match, rerun it with `sudo` to allow it traversing directories owned by other users)

For the rest of the document, FETCHD_HOME is assumed to be at the default `~/.fetchd` location. If your installation is different, replace `~/.fetchd` path in all the commands with your actual `FETCHD_HOME` path, and add the `--home <your_fetchd_home>` flag to all fetchd commands.

### Join discord channel

We'll setup a dedicated discord channel for the migration, where we'll share important information such as the block height we'll stop at, or validating `sha256sum` of the genesis file at each steps. Make sure to join it!

## Stop your validator

First, make sure your node have reached at least the `TODO_MIGRATION_BLOCK_HEIGHT` block height we will use to export the network state and restart from. You can configure your node in advance to stop at this height by setting the `halt-height` parameter in the `app.toml` file and restarting your node.
Also ensure that **no process managers (such as `systemd`) will attempt to restart it.**

The exact procedure to stop your node depends on how you configured it so we can't really give a generic way here.

Also double check it's properly stopped to avoid file corruption in the next steps.

## Backup FETCHD_HOME

Before making any changes, it's prefered to create a backup copy of your current `FETCHD_HOME` directory.

The following command can be used, assuming your `FETCHD_HOME` is `~/.fetchd/`:

```bash
cp -R ~/.fetchd/ ~/.fetchd_old/
```

This would allow to revert back to your starting state in case something goes wrong on the way.

## Export network state

```bash
fetchd export --height TODO_MIGRATION_BLOCK_HEIGHT > genesis_export_TODO_MIGRATION_BLOCK_HEIGHT.json
```

Generate a hash of this file and validate it with others:

```bash
sha256sum genesis_export_TODO_MIGRATION_BLOCK_HEIGHT.json
```

When your genesis hash matches the expected one, it's now time to update fetchd to the latest version.

## Reset the fetchd database

Now we have exported the state properly, we can drop the fetchd database:

> **Double check you have proper backups** of your FETCHD_HOME, and that the exported genesis is the correct one. `fetchd export` won't have anything to export anymore after this step!

```bash
fetchd unsafe-reset-all
```

## Install new fetchd version

You may already have the fetchd repository on your machine from the previous installation. If not, you can:

```bash
git clone --depth 1 --branch TODO_FETCHD_LATEST_TAG https://github.com/fetchai/fetchd.git fetchd_TODO_FETCHD_LATEST_TAG
cd fetchd_TODO_FETCHD_LATEST_TAG
``` 

If you already have an existing clone, place yourself in and:

```bash
git fetch
git checkout TODO_FETCHD_LATEST_TAG
```

Now you can install the new fetchd version:

```bash
make install

# and verify you now have the correct version:
fetchd version
# must print `TODO_FETCHD_LATEST_TAG`
```

## Update configuration

Configuration files received a lot of updates between versions, with quite a few new keys, and a couple of modified values on existing keys. The easiest way to update is to drop the existing configuration and integrate back your previous changes on top of the freshly generated config.

```bash
# safe to drop existing configs since we have made backups earlier
rm ~/.fetchd/config/app.toml ~/.fetchd/config/config.toml 

# fetchd will detect missing config files and regenerate new ones
fetchd version
```

Now you can edit `~/.fetchd/config/app.toml` and `~/.fetchd/config/config.toml` to add back any changes you made previously, or have a look at all the new settings.

> The new configuration include a lots of new comments and descriptions of the parameters, so worth reviewing in any cases.

## Migrate genesis

Now the new version of `fetchd` have proper configuration, we're ready to upgrade the genesis file to Stargate:

```bash
fetchd stargate-migrate \
    --chain-id TODO_NEW_CHAIN_ID \
    --genesis-time TODO_NEW_GENESIS_TIME \
    --initial-height TODO_MIGRATION_RESTART_BLOCK_HEIGHT \
    genesis_export_TODO_MIGRATION_BLOCK_HEIGHT.json > ~/.fetchd/config/genesis.json
```

We're setting here the new chainID, the time where the network will restart, and the initial block number 

Again, we'll hash the created genesis and ensure it matches the expected hash with other people:

```bash
sha256sum ~/.fetchd/config/genesis.json
``` 

Next, we'll introduce some changes in the genesis before restarting, to include MOBX tokens and migrate staked ERC20 tokens.

### Add MOBX genesis account

```bash
fetchd add-genesis-account TODO_MOBX_GENESIS_ACCOUNT 100000000000000000nanomobx
```

### Migrate staked ERC20 tokens

To ease the migration, we've extracted the staked ERC20 accounts and tokens into the [staked_erc20.csv file](./data/staked_export.csv). However, you can still replay the generation of this file and verify our scripts if you'd want to, by checking the [staking](./scripts/staking/) folder which contains the code and instructions needed.

To add the delegations to the genesis file, run:

```bash
./scripts/import_staked.sh ./data/staked_export.csv
```