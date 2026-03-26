class Wizmac < Formula
  desc "Shared macOS automation service and CLI"
  homepage "https://github.com/tanmayg1502/wizmac"
  license "MIT"
  head "https://github.com/tanmayg1502/wizmac.git", branch: "main"

  depends_on macos: :ventura

  def install
    system "swift", "build", "--configuration", "release", "--product", "wizmac"
    system "swift", "build", "--configuration", "release", "--product", "WizmacService"

    bin.install ".build/release/wizmac"
    bin.install ".build/release/WizmacService"
  end

  service do
    run [opt_bin/"WizmacService"]
    keep_alive true
  end

  test do
    system bin/"wizmac", "help"
    assert_predicate bin/"WizmacService", :exist?
    assert_predicate bin/"WizmacService", :executable?
  end
end
