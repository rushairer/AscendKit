class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.35.0/ascendkit-0.35.0-macos-arm64.tar.gz"
  sha256 "c12fd89cba94880ebc8c31975d459e5ced8d2b94d71efdd0dacfe6e40dd5d046"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
