# latest-fleetctl-package

Automated package builder for Fleet's command-line tool `fleetctl`. Get the latest version of `fleetctl` in `.pkg` format without managing dependencies or $PATH configurations.

## Features

- Automated package generation every 6 hours
- Pre-built macOS package (`.pkg`) for easy installation
- No dependencies required (`npm`, `brew`, etc.)
- `$PATH` configuration handled by installer
- Automated version tracking and updates

## Installation

1. Download the latest `.pkg` file from the [Releases](../../releases) page
2. Double-click the downloaded file to launch the installer
3. Follow the installation prompts
4. Verify installation by running:
   ```bash
   fleetctl version
   ```

Note: The `pkg` installer is unsigned, so if you install via double-clicking the `pkg` in Finder, you will get a message stating that it cannot be opened.
To avoid this, run the Installer app via the command line: `sudo installer -pkg /path/to/fleetctl_v#.#.#.pkg -target /`.
You can also allow the `pkg` to be installed through Finder by allow it through the Privacy & Security panel in System Settings.

The package installs `fleetctl` to `/usr/local/bin`

## How It Works

This repository uses GitHub Actions to automatically:
1. Check for new `fleetctl` releases every 6 hours
2. Generate a new macOS package when updates are detected
3. Create a new release with the built package

The automation uses [AutoPkg](https://github.com/autopkg/autopkg) with a recipe override that extends [jc0b's excellent recipes](https://github.com/autopkg/jc0b-recipes):
- The override ([`fleetctl.pkg.recipe.override.yml`](https://github.com/allenhouchins/latest-fleetctl-package/blob/main/autopkg-fleetctl/fleetctl.pkg.recipe.override.yml)) uses `ParentRecipe: com.github.jc0b.pkg.fleetctl` to inherit all functionality from jc0b's recipe
- Only the package naming convention is customized (`fleetctl_v%version%.pkg` instead of `fleetctl-v%version%`) to match our versioning scheme
- This approach ensures we automatically receive the latest recipe improvements and updates from jc0b while maintaining our specific packaging requirements
- No manual synchronization needed when jc0b updates his recipes

## Benefits Over Manual Installation

- No need to install Node.js or `npm`
- No Homebrew required
- Automatic `$PATH` configuration
- Official releases packaged as native macOS installers

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request or open an Issue.

## Acknowledgments

- [Fleet](https://github.com/fleetdm/fleet) - For creating and maintaining `fleetctl`
- [AutoPkg](https://github.com/autopkg/autopkg) - For the automation framework
- [jc0b](https://github.com/jc0b) - For creating the original AutoPkg recipes 

## Support

If you encounter any issues or have questions, please [open an issue](../../issues/new) in this repository.
