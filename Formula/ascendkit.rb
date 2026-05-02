class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.19.0/ascendkit-0.19.0-macos-arm64.tar.gz"
  sha256 "9b6a0d2abcaaca09cbb186076bd18dcf892b53337eb60cf61fbdd2fe90a81002"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
