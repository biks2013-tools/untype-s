cask "untype-studio" do
  version "0.9.0"
  sha256 "905d1ff926680c4e717ff15614d3b44bdc85559833b74e46a6810d9971ecea0d"

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
