# latest-fleetctl-package

Automated package builder for Fleet's command-line tool `fleetctl`. Get the latest version of `fleetctl` in `.pkg` format without managing dependencies or $PATH configurations.

## Features

- Automated package generation every 6 hours
- Pre-built macOS packages (`.pkg`) for easy installation
- No dependencies required (`npm`, `brew`, etc.)
- Proper PATH configuration handled by installer
- Automated version tracking and updates

## Installation

1. Download the latest `.pkg` file from the [Releases](../../releases) page
2. Double-click the downloaded file to launch the installer
3. Follow the installation prompts
4. Verify installation by running:
   ```bash
   fleetctl version
   ```

## How It Works

This repository uses GitHub Actions to automatically:
1. Check for new `fleetctl` releases every 6 hours
2. Generate a new macOS package when updates are detected
3. Create a new release with the built package
4. The package installs `fleetctl` to `/opt/fleetdm/fleetctl` and puts a symlink in `/usr/local/bin`

The automation uses [AutoPkg](https://github.com/autopkg/autopkg) with custom recipes:
- [`fleetctl.download.recipe`](https://github.com/allenhouchins/fleet-stuff/blob/main/autopkg-fleetctl/fleetctl.download.recipe) - Handles downloading the latest release
- [`fleetctl.pkg.recipe`](https://github.com/allenhouchins/fleet-stuff/blob/main/autopkg-fleetctl/fleetctl.pkg.recipe) - Generates the installer package

## Benefits Over Manual Installation

- No need to install Node.js or npm
- No Homebrew required
- Automatic PATH configuration
- Simple double-click installation
- Official releases packaged as native macOS installers

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.


## Acknowledgments

- [Fleet](https://github.com/fleetdm/fleet) - For creating and maintaining `fleetctl`
- [AutoPkg](https://github.com/autopkg/autopkg) - For the automation framework
- [homebysix-recipes](https://github.com/autopkg/homebysix-recipes/tree/master/VersionSplitter) - For VersionSplitter

## Support

If you encounter any issues or have questions, please [open an issue](../../issues/new) in this repository.
