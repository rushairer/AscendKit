class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.19.0/ascendkit-0.19.0-macos-arm64.tar.gz"
  sha256 "d94cb0f3c4cb556d6b536780a615db9fe28c4f77f69f73d541b7c2974f6bbe03"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
