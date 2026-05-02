class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.33.0/ascendkit-0.33.0-macos-arm64.tar.gz"
  sha256 "9cfbd48302fdce2454c57ec8c2bb562046175d0a97729fa35843867ac6dc5cff"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
