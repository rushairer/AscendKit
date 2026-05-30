class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.6.2/ascendkit-1.6.2-macos-universal.tar.gz"
  sha256 "cb231f9ee43fdf992e68ac8f6d8b140e9c86c6c6238c3d6f21432af2f4ab019e"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
