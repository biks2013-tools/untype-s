cask "untype-studio" do
  version "0.9.2"
  sha256 "6062e2a209bcd53ee702052772cf59a208a102a401265e3155ab76826a374846"

  url "https://github.com/biks2013-tools/untype-studio/releases/download/v#{version}/untype-studio-#{version}.zip"
  name "untype studio"
  desc "Explore recordings: transcripts, playback, cuts, Q&A and minutes"
  homepage "https://github.com/biks2013-tools/untype-studio"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :tahoe

  app "untype-studio.app"

  uninstall quit: "com.giorgosmarinos.untype-studio"

  zap trash: [
    "~/Library/Preferences/com.giorgosmarinos.untype-studio.plist",
    "~/Library/Saved Application State/com.giorgosmarinos.untype-studio.savedState",
  ]

  caveats <<~EOS
    untype studio opens the recordings ntakker saved (NTAKKER_RECORDINGS_DIR).
    It reads ntakker's settings file, ~/.tool-agents/ntakker/.env
    (Ask provider, keys, echo filter).
  EOS
end
