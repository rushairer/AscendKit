class Ascendkit < Formula
  desc "Local-first App Store release preparation toolkit"
  homepage "https://github.com/rushairer/AscendKit"
  url "https://github.com/rushairer/AscendKit/releases/download/v1.4.2/ascendkit-1.4.2-macos-universal.tar.gz"
  sha256 "b8836a57ac89e56edacc3409ffc4b94c2147d51ad0c61cc86f4b8bebf6cb2570"
  license "MIT"

  def install
    bin.install "bin/ascendkit"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/ascendkit --version")
  end
end
