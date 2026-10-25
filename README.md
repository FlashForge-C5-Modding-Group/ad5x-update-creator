# ad5x-update-creator

Builds a stock-format FlashForge AD5X update package (`AD5X-kalico-*.tgz`)
that flashes the Kalico MCU firmware — mainboard, eboard and IFS — using
FlashForge's own updater, so it works on a completely stock printer.

The AD5X analogue of `creator-5-update-creator` (the Creator 5 builder), with
the differences the AD5X brings: the outer package is a plain `.tgz` (stock
`app_startup.sh` unpacks it with `tar`, no encryption), and the MCU flashing
is the stock control part's `run.sh` (`IAPCommand` for the eboard,
`NationsCommand` for the mainboard, `ifsF37` + `IFSCommand` for the IFS).

## How the printer applies it

1. Put the built `.tgz` in `/usr/data` on the printer.
2. Power-cycle. Stock `app_startup.sh` unpacks it and runs its
   `flashforge_init.sh`, which md5-verifies and installs the control part
   into `/usr/prog/PROGRAM/control/<ver>/` with the `Update`/`UpdateM`
   markers set.
3. Power-cycle again. `app_startup.sh` sees the markers and runs the control
   part's `run.sh`: the eboard flashes in its power-on bootloader window, the
   mainboard through its ROM bootloader, the IFS after `ifsF37` drops it into
   its bootloader. The tools clear the markers and the printer reboots into
   the new firmware.

Going back to stock is the same procedure with an official FlashForge AD5X
update package.

## Build

```sh
AD5X_REFERENCE=/path/to/stock-AD5X-update.tgz ./build.sh
```

- `AD5X_REFERENCE` (required): an official AD5X update package (`.tgz` or an
  extracted copy). It supplies the updater layout and FlashForge's flash
  tools, which are not redistributed in this repository.
- `AD5X_FW_DIR` (default `../opencreator-fs/mcu-firmware/ad5x`): the Kalico
  images `AD5X-mainboard.bin`, `AD5X-eboard.hex`, `AD5X-ifs.hex`, verified
  against their `SHA256SUMS`.

Output in `dist/`: the `.tgz`, a `.sha256`, and a `.manifest.json` recording
the firmware version and checksums. The build round-trips the package and
re-verifies the control part before reporting success.
