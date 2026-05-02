class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.24.0/ascendkit-0.24.0-macos-arm64.tar.gz"
  sha256 "f1c0db46b10a2f987b589c35f5f03361f04f14e3cddf01236bddecd57e5ecb50"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
