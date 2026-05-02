class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v0.18.0/ascendkit-0.18.0-macos-arm64.tar.gz"
  sha256 "ce546e2f6800c9e842ffb5e0b15bb4759c3b56b8fbece1934930a7f90f6334e0"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
