class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.5.0/ascendkit-1.5.0-macos-universal.tar.gz"
  sha256 "2cf32bd9ddfd6e0140fe6c4163a1b34a6c8fa55e536dd9eee8c533113bda3801"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
