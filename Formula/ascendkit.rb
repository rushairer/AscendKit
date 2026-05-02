class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.17.0/ascendkit-0.17.0-macos-arm64.tar.gz"
  sha256 "1a491b02e54472cabf708b15fc8bfd0c447a5ed616807146fcc78f3a7eabc066"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
