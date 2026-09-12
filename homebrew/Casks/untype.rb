cask "untype" do
  version "0.1.0,13"
  sha256 "c76f01a0ef57de221201e2228fda57c597d6a7296ab78a344f47964a290be0d3"

  url "https://github.com/BikS2013/untype-s/releases/download/v#{version.csv.first}-b#{version.csv.second}/untype-#{version.csv.first}.dmg"
  name "untype"
  desc "Push-to-talk voice dictation with optional LLM refinement and translation"
  homepage "https://github.com/BikS2013/untype-s"

  livecheck do
    url :url
    regex(/^v?(\d+(?:\.\d+)+)-b(\d+)$/i)
    strategy :github_latest do |json, regex|
      match = json["tag_name"]&.match(regex)
      next if match.blank?

      "#{match[1]},#{match[2]}"
    end
  end

  depends_on macos: :sonoma

  app "untype.app"

  uninstall quit: "com.local.untype"

  zap trash: [
    "~/.tool-agents/untype/prompts",
    "~/.tool-agents/untype/release-latency.jsonl",
    "~/.tool-agents/untype/ui-state.json",
  ]

  caveats <<~EOS
    First launch:
      1. Click "Set keys..." on the welcome screen and enter at least one
         speech-to-text key (Soniox or ElevenLabs). Keys are stored in
         ~/.tool-agents/untype/.env, readable only by you.
      2. Click Start Listening once and allow the Microphone when macOS asks.
      3. System Settings > Privacy & Security > Accessibility > enable untype
         (needed for the push-to-talk hotkey and for inserting text into the
         focused field). Add untype under Input Monitoring too if the hotkey
         does not fire while another app is in front. Quit and relaunch after
         changing permissions.

    Technical deck: https://biks2013.github.io/untype-s/
    ~/.tool-agents/untype/.env is kept on uninstall and on zap.
  EOS
end
