# homebrew-untype

Homebrew tap for [untype](https://github.com/BikS2013/untype-s), push-to-talk voice dictation for macOS with optional LLM refinement and translation. The cask installs the notarized `untype.app` from the project's GitHub Releases.

## Install

```bash
brew tap BikS2013/untype
brew install --cask untype
```

## Upgrade

```bash
brew update
brew upgrade --cask untype
```

## After installation

1. Open untype and click **Set keys…** on the welcome screen; enter at least one speech-to-text key (Soniox or ElevenLabs). Keys are stored in `~/.tool-agents/untype/.env`, readable only by you.
2. Click **Start Listening** once and allow the **Microphone** when macOS asks.
3. **System Settings → Privacy & Security → Accessibility**: enable untype. Add it under **Input Monitoring** too if the hotkey does not fire while another app is in front. Quit and relaunch after changing permissions.

Technical deck: https://biks2013.github.io/untype-s/

## Uninstall

```bash
brew uninstall --cask untype        # removes the app, keeps ~/.tool-agents/untype
brew uninstall --zap --cask untype  # also removes prompts, UI state and the latency log; keeps .env
```

## Maintainers

This repository is the Homebrew tap that `brew tap BikS2013/untype` clones. It is maintained as a git subtree (`homebrew-tap/`) of the application repository [BikS2013/untype-s](https://github.com/BikS2013/untype-s): edit the cask there and push the subtree back here, never commit here directly. After each release:

```bash
# in untype-s
scripts/update-homebrew-cask.sh --version <version> --build <N> --sha256 <dmg sha256> --push
git push origin main
```
