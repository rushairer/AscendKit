class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.29.0/ascendkit-0.29.0-macos-arm64.tar.gz"
  sha256 "1752940e91c5226afb8dfa3d532e9b3c9b926832b46925c2d27b1788eb85ffa9"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
