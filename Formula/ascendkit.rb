class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.17.0/ascendkit-0.17.0-macos-arm64.tar.gz"
  sha256 "cbbe21def94ca99eb4257c056a2a6f73fa0dd76e54cddf2f65fec23a9fd1f94a"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
