class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.21.0/ascendkit-0.21.0-macos-arm64.tar.gz"
  sha256 "ae93305f00b26f797c55d011a6be0168dd8fd58ad022a75f85f840efc4d71430"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
