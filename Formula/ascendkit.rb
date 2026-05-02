class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.27.0/ascendkit-0.27.0-macos-arm64.tar.gz"
  sha256 "af9b898d4c9e6dd21d3a4f0f1458f67422a247c05bfd32ff7b4a75c5c277aba8"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
