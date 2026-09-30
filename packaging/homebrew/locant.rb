# specs/v0.9.md R69. The copy that ships lives in the tap, Malik1942/homebrew-locant, as
# Casks/locant.rb; scripts/cask.sh fills version and sha256 here after scripts/release.sh, and the
# file is copied over. Install: brew install Malik1942/locant/locant
cask "locant" do
  version "0.9.0"
  sha256 "75748ca6d365c93c3fd196d89207d04ac5f4c16bab37f0fb541c77c51afbf36f"

  url "https://github.com/Malik1942/locant/releases/download/v#{version}/Locant-#{version}.dmg"
  name "Locant"
  desc "Point at any UI element and hand a coding agent a grep-able reference"
  homepage "https://locant.malikzhang.com/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sequoia"

  app "Locant.app"

  # The captures in ~/Pictures/Locant are the user's and stay; the README's Uninstall section says
  # how to remove them, the two privacy grants, and the MCP entries in the agents' configurations.
  zap trash: [
    "~/Library/Preferences/com.malikzhang.deixis.plist",
    "~/Library/Saved Application State/com.malikzhang.deixis.savedState",
  ]
end
