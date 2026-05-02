class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.26.0/ascendkit-0.26.0-macos-arm64.tar.gz"
  sha256 "89632937f408df88e708f284f975e0953b722ba418ee21ccd26e4b98efbd89cf"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
