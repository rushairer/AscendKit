class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.7.0/ascendkit-1.7.0-macos-universal.tar.gz"
  sha256 "1b343b81d4cdb86df14d7b492030837e81887256ccded486b932c1a7a0590ae0"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
