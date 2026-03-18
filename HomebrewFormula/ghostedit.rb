cask "ghostedit" do
  version "1.3.0"
  sha256 "8ce7d303282607ce66f6a83a85663801386f5d8bb10312099a2c7155c2f43da5"

  url "https://github.com/nareshnavinash/ghostedit-electron/releases/download/v#{version}/GhostEdit-darwin-arm64.zip"
  name "GhostEdit"
  desc "AI text correction from the menu bar"
  homepage "https://nareshnavinash.github.io/ghostedit-electron/"

  app "GhostEdit-darwin-arm64/GhostEdit.app"

  zap trash: [
    "~/.ghostedit",
  ]
end
