class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.15.1/ascendkit-0.15.1-macos-arm64.tar.gz"
  sha256 "d1f0e04940436ab221409c6193d7391388dfbeeed53b13e511989aea78f040d1"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
