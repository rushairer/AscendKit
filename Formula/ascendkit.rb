class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.33.0/ascendkit-0.33.0-macos-arm64.tar.gz"
  sha256 "49c26c06a2093ce2646dbe2a167eedec1411242f69b71006186a5a172c01950a"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
