class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.32.0/ascendkit-0.32.0-macos-arm64.tar.gz"
  sha256 "24d0623e1756abc34ce72f3e31318ebbdcbb8403928572edb777f7ca0221a5b4"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
