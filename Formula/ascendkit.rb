class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.12.3/ascendkit-0.12.3-macos-arm64.tar.gz"
  sha256 "dfdd86d1a4c885a69f9b027bc044505fc41b2858de7adae79fef9b9819d65f47"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
