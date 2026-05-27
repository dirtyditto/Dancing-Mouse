# Homebrew Cask for Dancing Mouse.
#
# With this file in `Casks/`, this repo doubles as a Homebrew tap. After
# running `brew tap dirtyditto/dancing-mouse https://github.com/dirtyditto/Dancing_Mouse`,
# users can install via `brew install --cask dancing-mouse`.
#
# When cutting a new release:
#   1. Update `version` below to match the git tag (without the leading "v").
#   2. Replace the `sha256` value with the contents of the
#      `DancingMouse-<version>.dmg.sha256` file attached to the GitHub Release.
#      (Or leave `:no_check` for unsigned dev builds — not recommended for
#      published releases.)

cask "dancing-mouse" do
  version "1.0.0"
  sha256 :no_check # TODO: replace with the SHA-256 from the release's .sha256 file

  url "https://github.com/dirtyditto/Dancing_Mouse/releases/download/v#{version}/DancingMouse-#{version}.dmg"
  name "Dancing Mouse"
  desc "Menu-bar app that animates your cursor with playful patterns"
  homepage "https://github.com/dirtyditto/Dancing_Mouse"

  app "Dancing Mouse.app"

  zap trash: [
    "~/Library/Preferences/com.dancingmouse.app.plist",
    "~/Library/Saved Application State/com.dancingmouse.app.savedState",
  ]

  caveats <<~EOS
    Dancing Mouse needs Accessibility permission to move the cursor and
    detect user input. Grant it in:

      System Settings → Privacy & Security → Accessibility

    Then relaunch the app.
  EOS
end
