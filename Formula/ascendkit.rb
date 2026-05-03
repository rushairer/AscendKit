class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.2.0/ascendkit-1.2.0-macos-universal.tar.gz"
  sha256 "8685a54895dee4d1a79a2928b62e6b620bea8006b647afc52065805454adff8e"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
