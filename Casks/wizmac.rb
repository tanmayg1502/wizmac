cask "wizmac" do
  version :latest
  sha256 :no_check

  url "https://github.com/tanmayg1502/wizmac/releases/latest/download/Wizmac.zip"
  name "Wizmac"
  desc "Shared automation menu bar app, service, and CLI"
  homepage "https://github.com/tanmayg1502/wizmac"

  auto_updates true
  depends_on macos: :ventura

  app "Wizmac.app"
  binary "#{appdir}/Wizmac.app/Contents/Resources/bin/wizmac",
         target: "wizmac"

  uninstall quit: "com.tanmayg1502.wizmac"

  zap trash: [
    "~/Library/Application Support/Wizmac",
    "~/Library/Logs/Wizmac",
  ]
end
