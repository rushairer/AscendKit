class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.23.0/ascendkit-0.23.0-macos-arm64.tar.gz"
  sha256 "4c2cbf9e9d2cdb4679e033a7a9976f43eab847a574634760f1a17a9afeb27546"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
