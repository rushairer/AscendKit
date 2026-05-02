class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.29.0/ascendkit-0.29.0-macos-arm64.tar.gz"
  sha256 "a083065c053e7053d64b3c14969c7fe44b690816d426ce5cdb5fd04c30aa706a"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
