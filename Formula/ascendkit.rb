class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.4.3/ascendkit-1.4.3-macos-universal.tar.gz"
  sha256 "5820f58c2af0b3767f8444be9ad3a63ac93355429ba75f5f51d99b219f004e09"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
