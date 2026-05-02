class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.32.0/ascendkit-0.32.0-macos-arm64.tar.gz"
  sha256 "20cf1108b90c4084b5f61fd44abc0b7278f49cf7a6c6ef995165436804639f3d"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
