class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.28.0/ascendkit-0.28.0-macos-arm64.tar.gz"
  sha256 "eef0a2bf5ece58c94cb48fe12be8420b22b18be0e6b435c9c047ace8c3c10266"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
