class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.34.0/ascendkit-0.34.0-macos-arm64.tar.gz"
  sha256 "a61e4ab1e557646f95f5b99d5f4e029f95406af71fc99513a0453e16757a9b98"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
